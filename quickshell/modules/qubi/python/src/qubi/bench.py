#!/usr/bin/env python3
"""qubi-bench: acceptance gates against the real, running qubi-engine.

Phase 9 (qubi-engine night 2). Unlike goose-bench.nix's gooseBench (which
drives a bare `goose run --no-session` per model, bypassing the engine
entirely for raw model-selection comparisons), this talks JSON-RPC over
the real engine socket -- the same protocol GooseAcpSession.qml speaks --
so what it measures is the actual deployed system: routing, the escalate
tool's real shape, and real per-tier latency, not a model in isolation.

Gate thresholds live in .agents/bench/gates.json, not hardcoded here, so
Liam can retune them without touching this file. Reuses
~/.config/qubi/config.json's own latency_budgets for the latency gate
rather than duplicating that number in a second place.

Four of the seven gates (tool-format, no-tool, escalation-accuracy,
latency) share one set of real live turns against the target tier rather
than each spawning its own -- the light tier's own measured TTFT is
17-40s per turn (see .agents/bench/2026-09-19-latency.md), so reusing
turns across gates keeps one `acceptance` run from taking many minutes
longer than it needs to.

Each case gets its own fresh connection (not one connection reused
across cases) and simply waits out the real turn rather than trying to
session/cancel and move on early -- an earlier version tried the latter
and hit real trouble: confirmed live that this tier serializes turns at
the underlying `goose acp` process level (a completely unrelated
session's `session/new` blocked for 100+s behind another session's
still-running generation), and `session/cancel` did not reliably free it
up when sent while a turn was mid-flight. Simpler and slower beats
clever and flaky here.

append-vs-overwrite and no-phantom-write need real file-mutation tools
(the `developer` extension) -- the light tier deliberately has none
(only `escalate`, confirmed live via ~/.config/qubi/config.json), so
those two gates report a real "skip" with the reason, never a faked
pass, when run with --tier light.

game-qa is read-only: /run/ai-workstation/state.json is root-owned (this
CLI must never sudo to flip it), so the gate can only assert consistency
against whatever gaming state is real right now, not force one.
"""
import argparse
import json
import os
import socket
import sys
import time

from . import config as qubi_config
from . import paths

GATES_PATH = os.environ.get("QUBI_BENCH_GATES") or os.path.join(os.path.dirname(__file__), "data", "gates.json")

# should_escalate=True is a deliberately unambiguous multi-file/careful-
# reasoning ask (the escalate tool's own description's trigger language);
# False is a trivial single-fact question -- these two reused turns are
# what tool-format/no-tool/escalation-accuracy/latency are all graded
# from. Kept to n=2 (not a larger sample) given the real per-tier
# serialization cost above -- escalation-accuracy's own min_pass_rate in
# gates.json is deliberately 1.0 at this sample size (0.8 of 2 rounds
# down to "1 wrong is still a pass," which would defeat the gate).
ESCALATION_CASES = [
    {"prompt": "Please rewrite our entire authentication system across every file in this codebase, carefully handling the database migrations.", "should_escalate": True},
    {"prompt": "What is 6 times 7? Answer with just the number.", "should_escalate": False},
]


class EngineClient:
    # Deliberately NOT socket.makefile() -- confirmed live that once one
    # of its buffered readline() calls times out (needed for
    # call_bounded's deadline), every subsequent read raises `OSError:
    # cannot read from timed out object` instead of cleanly retrying
    # (CPython's buffered-reader-over-a-timing-out-socket wrapper doesn't
    # recover). Rolling a tiny own line buffer over raw recv() avoids that
    # failure mode entirely -- a timed-out recv() just means "no full line
    # yet," not a broken stream.
    def __init__(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(paths.socket_path(qubi_config.load()))
        self._buf = b""
        self._id = 1

    def _send(self, method, params):
        req_id = self._id
        self._id += 1
        self.sock.sendall((json.dumps({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}) + "\n").encode())
        return req_id

    def _readline(self):
        """Returns one decoded line, or None if the read timed out before a
        full line was available (caller decides whether to keep waiting)."""
        while b"\n" not in self._buf:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                return None
            if not chunk:
                raise ConnectionError("qubi-engine closed the connection (is qubi-engine.service running?)")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\n", 1)
        return line.decode(errors="replace")

    def call(self, method, params, timeout=120, on_notification=None):
        req_id = self._send(method, params)
        self.sock.settimeout(timeout)
        while True:
            line = self._readline()
            if line is None:
                raise TimeoutError(f"{method} timed out after {timeout}s waiting for a response")
            obj = json.loads(line)
            if obj.get("id") == req_id and ("result" in obj or "error" in obj):
                return obj.get("result"), obj.get("error")
            if on_notification:
                on_notification(obj)

    def call_bounded(self, method, params, deadline_s, on_notification):
        """Like call(), but on_notification can return True to stop early
        (signal already captured), and an overall wall-clock deadline caps
        total wait even if the matching response id never arrives -- real,
        not hypothetical: confirmed live that the light-tier model doesn't
        reliably honor escalate.py's own "stop here and wait" instruction,
        so a turn can keep generating well past the point its tool_call
        already told us everything we needed. Returns True only if the
        real session/prompt result/error arrived before deadline_s."""
        req_id = self._send(method, params)
        deadline = time.monotonic() + deadline_s
        self.sock.settimeout(2.0)
        while time.monotonic() < deadline:
            line = self._readline()
            if line is None:
                continue
            obj = json.loads(line)
            if obj.get("id") == req_id and ("result" in obj or "error" in obj):
                return True
            if on_notification(obj):
                return False
        return False

    def close(self):
        self.sock.close()


def load_gates():
    with open(GATES_PATH) as f:
        return json.load(f)["gates"]


def run_turn(client, session_id, prompt_text, deadline_s=90):
    """One real session/prompt turn, bounded. Returns (tool_calls,
    message_text, ttft_ms, completed). completed=False means we stopped
    early (an escalate tool_call already told us what we needed) or hit
    the deadline without the model ever finishing on its own -- either
    way, a session/cancel is sent afterward so the tier doesn't keep
    grinding on a turn this suite has already stopped listening to."""
    tool_calls = []
    message_parts = []
    start = time.monotonic()
    ttft_ms = None

    def on_notification(obj):
        nonlocal ttft_ms
        if obj.get("method") != "session/update":
            return False
        upd = obj.get("params", {}).get("update", {})
        kind = upd.get("sessionUpdate")
        if ttft_ms is None and kind in ("agent_message_chunk", "agent_thought_chunk"):
            ttft_ms = (time.monotonic() - start) * 1000
        if kind == "tool_call":
            tool_calls.append(upd)
            if "escalate" in tool_name_of(upd).lower():
                return True  # signal captured, stop waiting on this turn
        elif kind == "agent_message_chunk":
            message_parts.append(upd.get("content", {}).get("text", ""))
        return False

    completed = client.call_bounded("session/prompt", {
        "sessionId": session_id,
        "prompt": [{"type": "text", "text": prompt_text}],
    }, deadline_s, on_notification)
    if not completed:
        client._send("session/cancel", {"sessionId": session_id})
    return tool_calls, "".join(message_parts), ttft_ms, completed


def tool_name_of(tool_call):
    meta = (tool_call.get("_meta", {}) or {}).get("goose", {}).get("toolCall", {}) or {}
    return meta.get("toolName") or tool_call.get("title", "")


def cmd_acceptance(args):
    tier = args.tier
    cfg = qubi_config.load()
    tier_cfg = cfg["tiers"][tier]
    gates = load_gates()
    results = {}

    if "developer" not in tier_cfg["extensions"]:
        for name in ("append-vs-overwrite", "no-phantom-write"):
            results[name] = {"status": "skip", "reason": f"{tier} tier has no file-mutation tools (extensions: {tier_cfg['extensions']})"}
    else:
        for name in ("append-vs-overwrite", "no-phantom-write"):
            results[name] = {"status": "skip", "reason": "not implemented tonight for a tool-bearing tier -- Phase 9 exercised --tier light live; extend here before running against heavy/claude"}

    client = EngineClient()
    try:
        init_result, err = client.call("initialize", {"protocolVersion": 1})
        if err:
            raise RuntimeError(f"initialize failed: {err}")

        # A fresh session per case (still over the one connection -- that
        # part was never the issue). session/new's own timeout here is
        # deliberately generous (200s): confirmed live that a still-
        # running previous turn on this tier can leave even a completely
        # unrelated session's session/new queued for 100+ seconds behind
        # it (real tier-level serialization in the underlying `goose acp`
        # process, not a bug in this script) -- see this file's own
        # header comment.
        cases = []
        for case in ESCALATION_CASES:
            new_result, err = client.call("session/new", {"cwd": paths.default_cwd(qubi_config.load()), "mcpServers": []}, timeout=200)
            if err:
                raise RuntimeError(f"session/new failed: {err}")
            session_id = new_result["sessionId"]
            tool_calls, message_text, ttft_ms, completed = run_turn(client, session_id, case["prompt"])
            escalate_calls = [tc for tc in tool_calls if "escalate" in tool_name_of(tc).lower()]
            cases.append({**case, "escalate_calls": escalate_calls, "any_tool_calls": tool_calls, "message_text": message_text, "ttft_ms": ttft_ms, "completed": completed})
            print(f"[qubi-bench]   turn done: escalated={bool(escalate_calls)} expected={case['should_escalate']} ttft={ttft_ms and round(ttft_ms)}ms completed={completed}", file=sys.stderr)
    finally:
        client.close()

    # tool-format: the first case that really escalated, checked for a
    # well-formed rawInput (reason + suggested_tier in the real enum
    # escalate.py declares).
    escalated_cases = [c for c in cases if c["escalate_calls"]]
    if escalated_cases:
        raw = escalated_cases[0]["escalate_calls"][0].get("rawInput") or {}
        ok = bool(raw.get("reason")) and raw.get("suggested_tier") in ("heavy_local", "claude")
        results["tool-format"] = {"status": "pass" if ok else "fail", "detail": raw}
    else:
        results["tool-format"] = {"status": "fail", "detail": "no case triggered a real escalate tool_call to grade"}

    # no-tool: every case that should NOT escalate must have zero tool
    # calls of any kind, not just zero escalate calls.
    no_tool_cases = [c for c in cases if not c["should_escalate"]]
    no_tool_ok = all(len(c["any_tool_calls"]) == 0 for c in no_tool_cases)
    results["no-tool"] = {"status": "pass" if no_tool_ok else "fail", "detail": [len(c["any_tool_calls"]) for c in no_tool_cases]}

    # escalation-accuracy: fraction of all cases where actual behavior
    # (escalated or not) matched should_escalate.
    correct = sum(1 for c in cases if bool(c["escalate_calls"]) == c["should_escalate"])
    rate = correct / len(cases)
    min_rate = gates["escalation-accuracy"]["min_pass_rate"]
    results["escalation-accuracy"] = {"status": "pass" if rate >= min_rate else "fail", "rate": rate, "min_pass_rate": min_rate}

    # latency: real TTFT vs this tier's real configured budget -- reported
    # honestly even though Phase 6 already found this fails for light
    # (measured 17-39s vs a 1500ms budget; the root cause -- a reasoning
    # model that "thinks" before answering -- is a model/config decision
    # for Liam, not something this gate should hide by loosening itself).
    ttfts = [c["ttft_ms"] for c in cases if c["ttft_ms"] is not None]
    budget_key = f"{tier}_ttft_ms"
    budget_ms = cfg.get("latency_budgets", {}).get(budget_key)
    p_worst = max(ttfts) if ttfts else None
    lat_ok = budget_ms is not None and p_worst is not None and p_worst <= budget_ms
    results["latency"] = {"status": "pass" if lat_ok else "fail", "worst_ttft_ms": p_worst, "budget_ms": budget_ms, "all_ttft_ms": ttfts}

    # game-qa: read-only, asserts consistency against whatever real gaming
    # state exists right now rather than forcing one (the state file is
    # root-owned; this CLI never sudo's to flip it).
    try:
        with open(paths.hw_state_file(qubi_config.load())) as f:
            gaming_state = json.load(f)
        is_gaming = gaming_state.get("state") == "gaming"
    except (FileNotFoundError, json.JSONDecodeError):
        is_gaming = False
    if not is_gaming:
        results["game-qa"] = {"status": "skip", "reason": f"not currently in gaming state ({paths.hw_state_file(qubi_config.load())})"}
    else:
        status_client = EngineClient()
        try:
            status_result, err = status_client.call("qubi/status", {})
        finally:
            status_client.close()
        reported_model = (status_result or {}).get("tiers", {}).get("light", {}).get("model")
        ok = reported_model == tier_cfg.get("cpu_model")
        results["game-qa"] = {"status": "pass" if ok else "fail", "reported_model": reported_model, "expected_cpu_model": tier_cfg.get("cpu_model")}

    print(f"\n[qubi-bench] acceptance --tier {tier}\n")
    overall_pass = True
    for name in ("tool-format", "no-tool", "escalation-accuracy", "append-vs-overwrite", "no-phantom-write", "latency", "game-qa"):
        r = results[name]
        print(f"  {name:22} {r['status'].upper()}")
        if r["status"] == "fail":
            overall_pass = False
    print(f"\n  overall: {'PASS' if overall_pass else 'FAIL (see BLOCKERS.md/PROGRESS.md for known, not-hidden failures)'}")

    out_path = os.path.expanduser(f"~/.local/share/qubi-bench/acceptance-{tier}.json")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        json.dump({"tier": tier, "results": results, "cases": cases, "overall_pass": overall_pass}, f, indent=2, default=str)
    print(f"\n  full results: {out_path}")
    return 0 if overall_pass else 1


def main():
    p = argparse.ArgumentParser(prog="qubi-bench")
    sub = p.add_subparsers(dest="cmd", required=True)

    acc = sub.add_parser("acceptance", help="run the acceptance gate suite against the real engine")
    acc.add_argument("--tier", default="light", choices=["light", "heavy", "claude"])
    acc.set_defaults(func=cmd_acceptance)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
