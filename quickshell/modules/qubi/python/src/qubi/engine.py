#!/usr/bin/env python3
"""qubi-engine: one persistent daemon, many clients, per-turn tier routing.

Promotes goose_bridge.py's proven "one shared process, fan out to every
subscriber" idea from a single dumb relay into a real multi-tier router that
still speaks bare ACP JSON-RPC to every client -- a client that used to
spawn `goose acp` directly (GooseAcpSession.qml) only needs its transport
swapped (socket instead of stdio); every method/id/notification it already
understands still means exactly the same thing on the other side of this
daemon. See DECISIONS.md for the specific per-phase calls made building this.

Transports:
  - $XDG_RUNTIME_DIR/qubi/engine.sock (Unix socket) -- desktop clients.
  - 127.0.0.1:8765 (WebSocket) -- mobile, behind tailscale serve, same as
    goose_bridge.py before it.
Both carry the identical message shape: one JSON object per line/frame,
either a real ACP JSON-RPC message (forwarded to/from a tier's `goose acp`
process, request ids remapped so concurrent clients can't collide) or a
`qubi/*`-namespaced engine method (handled here, never forwarded).
"""
import asyncio
import json
import os
import re
import subprocess
import time

import websockets
import yaml
from websockets.exceptions import ConnectionClosed

import qubi_config

REPO_ROOT = os.path.expanduser("~/nix-dots")
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
SOCKET_PATH = os.path.join(RUNTIME_DIR, "qubi", "engine.sock")
TIERCONF_DIR = os.path.join(RUNTIME_DIR, "qubi", "tierconf")
BASE_GOOSE_CONFIG = os.path.expanduser("~/.config/goose/config.yaml")

# Written by modules/nixos/apps/ai-workstation.nix on every dock/undock/
# gaming transition (and reconciled at boot by ai-workstation-boot-sync).
# `state` is one of docked / undocked / gaming. Despite this engine
# originally only caring about the gaming value, the file is not
# gaming-specific -- see _read_hw_state below.
HW_STATE_FILE = "/run/ai-workstation/state.json"

# The two states with no GPU available for local inference. `gaming` means
# the eGPU is present but deliberately reserved for the game (Phase 5b);
# `undocked` means there is physically no eGPU at all. They differ in what
# else changes (see _hw_watch_loop) but they agree on the one thing that
# picks a model tag: inference lands on the CPU, so a tier's `cpu_model`
# is the correct tag rather than its GPU-tuned `model`.
CPU_ONLY_STATES = ("gaming", "undocked")


def log(*a):
    print("[qubi-engine]", *a, flush=True)


# --------------------------------------------------------------------------
# Per-tier goose config generation
# --------------------------------------------------------------------------

def build_tier_config_dir(tier_name, tier_cfg, extra_extensions=None, model=None):
    """Writes an isolated $XDG_CONFIG_HOME/goose/config.yaml for this tier:
    same base config Liam already has (auth, provider credentials, every
    extension's real cmd path) but with `extensions.*.enabled` rewritten to
    exactly this tier's list. Confirmed live (Phase 0 probing, before this
    file existed) that XDG_CONFIG_HOME isolation is real and that Goose
    reads it per-process -- this is not a guess.

    The `escalate` tool is not a real installed Goose extension (there is
    no cmd for it in Liam's actual config.yaml), so it's synthesized here
    directly into the tier's own config when the tier's extension list asks
    for it -- this is the ONLY place escalate.py's stdio server is wired in,
    deliberately never added to the real ~/.config/goose/config.yaml so it
    can never leak into the heavy/claude tiers by accident.
    """
    # yaml.safe_load, not json.load: confirmed live that this file is
    # genuine block-style YAML, not the flow-style/JSON-compatible content
    # it happened to be early in this build -- a real runtime write from
    # Goose itself (e.g. an interactive `/model` change persisting back to
    # disk, confirmed via a live `providers.claude-code.model` value this
    # session never set) can turn it into real YAML at any time. JSON is a
    # syntactic subset of YAML, so this reads either form correctly.
    with open(BASE_GOOSE_CONFIG) as f:
        base = yaml.safe_load(f)

    cfg = dict(base)
    # extra_extensions: gaming-only additions (Phase 5d -- light tier gets
    # searxng while gaming, since game questions are usually web questions
    # and web lookup costs the game's own GPU/CPU nothing) that aren't part
    # of the tier's normal, always-on extension list from config.json.
    wanted = set(tier_cfg["extensions"]) | set(extra_extensions or [])
    exts = {}
    for name, e in base["extensions"].items():
        e2 = dict(e)
        e2["enabled"] = name in wanted
        exts[name] = e2
    if "escalate" in wanted and "escalate" not in exts:
        exts["escalate"] = {
            "bundled": False,
            "cmd": os.environ.get("QUBI_PY", "python3"),
            "description": "Escalate to a bigger model instead of guessing",
            "display_name": "Escalate",
            "enabled": True,
            "name": "escalate",
            "timeout": 30,
            "type": "stdio",
            # Goose's stdio extension launcher takes cmd+args as a single
            # exec vector; passing the script as the first arg after the
            # interpreter matches how e.g. notes-capture's own wrapper
            # script (a single exec line) is invoked -- here inlined since
            # there's no Nix-built wrapper for a dev-loop script like this.
            "args": [os.path.join(REPO_ROOT, "engine", "escalate.py")],
        }
    cfg["extensions"] = exts

    # Rewrite the model/provider keys to THIS tier's, not the base config's.
    #
    # Without this the tier config is a verbatim copy of
    # ~/.config/goose/config.yaml apart from `extensions`, so every tier
    # inherited that file's model (qwen3:4b) no matter what the tier asked
    # for. The GOOSE_MODEL env var set in ensure_started does not reliably
    # win over the config file, which is exactly the leak BLOCKERS.md
    # already recorded for the claude tier ("it leaks the wrong model
    # (qwen3:4b) into a claude-code-provider session and every prompt
    # fails") -- same root cause, and it silently affected every tier.
    #
    # Caught by A/B measurement: the `fast` tier, configured for
    # llama3.2:3b, answered in 53s while emitting 1935 characters of
    # reasoning. llama3.2 has no reasoning mode and answers the same prompt
    # in 147ms when called directly, so the tier was plainly still running
    # qwen3 -- and its generated config.yaml confirmed it.
    provider = tier_cfg.get("provider")
    if provider:
        cfg["GOOSE_PROVIDER"] = provider
        cfg["active_provider"] = provider
    if model:
        cfg["GOOSE_MODEL"] = model
    providers = dict(cfg.get("providers") or {})
    if provider and model:
        entry = dict(providers.get(provider) or {})
        entry["model"] = model
        providers[provider] = entry
        cfg["providers"] = providers

    tier_dir = os.path.join(TIERCONF_DIR, tier_name, "goose")
    os.makedirs(tier_dir, exist_ok=True)
    with open(os.path.join(tier_dir, "config.yaml"), "w") as f:
        json.dump(cfg, f)
    return os.path.join(TIERCONF_DIR, tier_name)


# --------------------------------------------------------------------------
# One tier's `goose acp` process
# --------------------------------------------------------------------------

class TierProcess:
    def __init__(self, name, tier_cfg, on_notification):
        self.name = name
        self.tier_cfg = tier_cfg
        self.on_notification = on_notification  # async fn(tier_name, notification_obj)
        self.proc = None
        self.ready = asyncio.Event()
        self.starting = False
        self._next_id = 1
        self._pending = {}  # internal_id -> asyncio.Future
        self.last_activity = time.monotonic()
        self._reader_task = None
        # Per-tier overridable, so a future tier on much faster or much
        # slower hardware doesn't have to share these. See the long comment
        # in ensure_started for why one value can't cover both states.
        #
        # 2048 rather than something tighter: measured undocked, a trivial
        # prompt ("Say exactly: pong") already draws ~1500 tokens out of
        # qwen3:4b, because it narrates its reasoning as ordinary content
        # no matter what -- GOOSE_LOCAL_ENABLE_THINKING=false and Ollama's
        # own `think: false` only move that text out of the `thinking`
        # field and into the visible answer, and qwen3's `/no_think` prompt
        # switch merely halves it (196 -> 104 tokens on the same prompt).
        # So a cap under ~1500 would truncate *typical* replies rather than
        # only runaway ones. 2048 bounds the worst case to roughly 5
        # minutes instead of 9+ while leaving normal turns intact.
        self.gpu_max_tokens = tier_cfg.get("max_tokens", 4096)
        self.cpu_max_tokens = tier_cfg.get("cpu_max_tokens", 2048)

    async def ensure_started(self, cpu_override=False, extra_extensions=None):
        if self.proc is not None and self.proc.returncode is None:
            return
        self.starting = True
        self.ready.clear()
        model = self.tier_cfg["cpu_model"] if cpu_override else self.tier_cfg["model"]
        config_home = build_tier_config_dir(self.name, self.tier_cfg, extra_extensions=extra_extensions, model=model)
        env = dict(os.environ)
        env["XDG_CONFIG_HOME"] = config_home
        env["GOOSE_PROVIDER"] = self.tier_cfg["provider"]
        if model:
            env["GOOSE_MODEL"] = model
        env["GOOSE_LOCAL_ENABLE_THINKING"] = "false"
        # Real, live-confirmed bug fix (Phase 9 acceptance-suite testing):
        # without a cap, a local model that doesn't honor escalate.py's own
        # "stop here and wait" instruction can keep generating for 4+
        # minutes after already calling the escalate tool -- and because
        # this single goose acp process serializes ALL sessions on this
        # tier (confirmed live: a completely unrelated session's plain
        # session/new blocked 200+s behind another session's still-running
        # turn), one rambling turn blocks the entire tier for everyone,
        # not just its own session. goose.nix's own CLI wrappers
        # (qubi-code, qubi-claude) already set this for exactly this
        # reason ("Tool arguments ... were truncated" was the original
        # motivating bug there) -- the engine's tier processes never
        # inherited it. Same value, same rationale, now here too.
        #
        # The cap is in TOKENS but the thing it exists to bound is SECONDS,
        # and the conversion rate between them is generation speed -- so a
        # single number can't bound both hardware states. Measured on this
        # box: qwen3:4b runs 81 tok/s on the docked eGPU (4096 tokens =>
        # ~50s worst case, which is what this value was chosen against) but
        # only ~7.4 tok/s CPU-only, degrading as the KV cache grows (4096
        # tokens => 9+ minutes). Confirmed live while undocked: "Say
        # exactly: pong. Nothing else." on the light tier generated 1544
        # tokens over 3m34s and stopped on its own -- comfortably under
        # 4096, so the cap never engaged at all and the turn simply ran to
        # completion. A GPU-calibrated ceiling is no ceiling on CPU.
        max_tokens = self.cpu_max_tokens if cpu_override else self.gpu_max_tokens
        env["GOOSE_MAX_TOKENS"] = str(max_tokens)
        log(f"{self.name}: spawning goose acp (provider={self.tier_cfg['provider']} "
            f"model={model or '(default)'} max_tokens={max_tokens})")
        t0 = time.monotonic()
        self.proc = await asyncio.create_subprocess_exec(
            "goose", "acp",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            env=env,
        )
        self._reader_task = asyncio.create_task(self._read_loop())
        await self.call("initialize", {"protocolVersion": 1})
        self.ready.set()
        self.starting = False
        log(f"{self.name}: ready in {(time.monotonic() - t0) * 1000:.0f}ms")

    async def _read_loop(self):
        while True:
            line = await self.proc.stdout.readline()
            if not line:
                break
            s = line.decode(errors="replace").strip()
            if not s:
                continue
            try:
                obj = json.loads(s)
            except json.JSONDecodeError:
                continue
            self.last_activity = time.monotonic()
            if obj.get("id") is not None and ("result" in obj or "error" in obj) and obj["id"] in self._pending:
                fut = self._pending.pop(obj["id"])
                if not fut.done():
                    fut.set_result(obj)
                continue
            # Everything else is a notification or an agent-initiated
            # request (session/request_permission) -- both get relayed
            # upstream for fan-out/interception.
            await self.on_notification(self.name, obj)
        log(f"{self.name}: goose acp exited (code {self.proc.returncode if self.proc else '?'})")
        self.ready.clear()

    async def call(self, method, params, timeout=300):
        rid = self._next_id
        self._next_id += 1
        fut = asyncio.get_running_loop().create_future()
        self._pending[rid] = fut
        self.proc.stdin.write((json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}) + "\n").encode())
        await self.proc.stdin.drain()
        self.last_activity = time.monotonic()
        return await asyncio.wait_for(fut, timeout=timeout)

    def send_raw(self, obj):
        """Fire-and-forget write (used for relaying a permission RESPONSE
        from a client back into this process -- that's a JSON-RPC response
        to an agent-initiated request, not something we wait on)."""
        self.proc.stdin.write((json.dumps(obj) + "\n").encode())
        asyncio.create_task(self.proc.stdin.drain())

    async def stop(self):
        if self._reader_task:
            self._reader_task.cancel()
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()
            try:
                await asyncio.wait_for(self.proc.wait(), timeout=5)
            except asyncio.TimeoutError:
                self.proc.kill()
        self.proc = None
        self.ready.clear()


# --------------------------------------------------------------------------
# Heuristic pre-router (Phase 3a) -- zero-latency, pure string scoring, no
# model call. Deliberately conservative: only routes straight to "heavy" on
# strong syntactic signals (code fence, long message, explicit file path in
# a git repo). A moderate-length natural-language request that merely uses
# a word like "refactor" stays on light and relies on light's own judgment
# (the escalate tool) -- confirmed as the right split by Phase 0's own
# finding that tool-schema bloat, not tier choice, is the dominant latency
# cost, so keeping the default path light is worth a少 hard prompts round-
# tripping through one escalate call.
# --------------------------------------------------------------------------

HEAVY_VERBS = ("refactor", "implement", "design", "migrate", "rewrite", "architect")


def score_prompt(text, cwd_is_git_repo=True):
    score = 0
    reasons = []
    if "```" in text:
        score += 5
        reasons.append("contains a code fence")
    if len(text) > 400:
        score += 3
        reasons.append(f"long message ({len(text)} chars)")
    if any(tok in text for tok in ("/home", "/nix-dots", "./")) and cwd_is_git_repo:
        score += 2
        reasons.append("mentions a file path")
    verb_hits = [v for v in HEAVY_VERBS if v in text.lower()]
    if verb_hits:
        score += 1
        reasons.append(f"verb signal: {verb_hits}")
    tier = "heavy" if score >= 5 else "light"
    return tier, score, reasons


# --------------------------------------------------------------------------
# Session registry + fan-out
# --------------------------------------------------------------------------

class Session:
    def __init__(self, session_id, tier):
        self.id = session_id
        self.tier = tier
        self.status = "idle"
        # Finer-grained than `status`, purely for the UI's activity
        # indicator. `status` says whether a turn is in flight; `phase` says
        # WHAT is taking the time, which is the difference between a panel
        # that looks frozen and one that looks busy. Measured on a real
        # docked turn: a trivial prompt spent ~16s with nothing at all sent
        # to the client, because the only two status pushes are "working" at
        # dispatch and "done" at the end. Every long-running step below now
        # names itself here instead.
        self.phase = "idle"
        # Short rolling description of what the model is reasoning about,
        # derived from the reasoning stream (first line of the newest
        # agent_thought_chunk, truncated). Deliberately NOT a second model
        # call -- summarising the summary would cost more than the turn.
        self.phase_detail = ""
        self.last_activity = time.monotonic()
        self.subscribers = set()  # ClientConn set
        self.last_user_prompt = None
        self.prompt_queue = []  # (ClientConn, params, respond_future)
        self.busy = False

        # One goose session per tier, because goose pins the model onto the
        # session row at session/new time:
        #   sessions.model_config_json = {"model_name": "qwen3:4b", ...}
        # session/load then RESTORES that pinned model, so the old design
        # (one goose session, session/load'ed onto whichever tier) silently
        # ran every tier on whatever model created the session. Proven by
        # unloading llama3.2 and watching a switch to the llama3.2-configured
        # `fast` tier never reload it -- it was still answering from qwen3.
        # Setting GOOSE_MODEL, the tier config's GOOSE_MODEL, and
        # providers.<p>.model all failed to override the pin.
        #
        # `self.id` stays the stable, client-facing id for the whole
        # conversation; these are the per-tier aliases the engine talks to
        # goose with. Clients never see them -- notifications are rewritten
        # back to self.id on the way out.
        self.tier_sessions = {tier: session_id}

        # Conversation to replay into the next tier's fresh goose session.
        # A brand-new session has no history, and escalation exists
        # precisely to hand a hard problem to a bigger model *with* its
        # context, so the transcript is carried over as a preamble on the
        # first prompt after a switch.
        self.pending_context = None

    def tier_sid(self, tier=None):
        """The goose session id to use when talking to `tier`."""
        t = tier or self.tier
        return self.tier_sessions.get(t, self.id)


class ClientConn:
    """Wraps either a Unix-socket StreamWriter or a websocket connection
    behind the same send()/subscriptions interface."""
    _counter = 0

    def __init__(self, kind, writer):
        ClientConn._counter += 1
        self.cid = ClientConn._counter
        self.kind = kind  # "socket" | "ws"
        self.writer = writer
        self.subscriptions = set()

    async def send(self, obj):
        data = (json.dumps(obj) + "\n")
        try:
            if self.kind == "socket":
                self.writer.write(data.encode())
                await self.writer.drain()
            else:
                await self.writer.send(data)
        except (ConnectionClosed, ConnectionResetError, BrokenPipeError):
            pass


# --------------------------------------------------------------------------
# The engine itself
# --------------------------------------------------------------------------

class Engine:
    def __init__(self, cfg):
        self.cfg = cfg
        self.tiers = {}
        # Driven by the config rather than a hardcoded triple, so adding a
        # tier (e.g. "fast") is a config edit, not a code change. The three
        # below are still required -- routing, escalation and the light-tier
        # hardware bounce all name them directly -- so a config missing one
        # is a startup error rather than a mysterious KeyError later.
        for required in ("light", "heavy", "claude"):
            if required not in cfg["tiers"]:
                raise SystemExit(f"[qubi-engine] config is missing the required '{required}' tier")
        for name in cfg["tiers"]:
            self.tiers[name] = TierProcess(name, cfg["tiers"][name], self._on_tier_notification)
        self.sessions = {}  # client-facing session_id -> Session
        # goose's per-tier session id -> Session. Notifications arrive
        # stamped with the tier's own alias, so this is how a chunk gets
        # routed back to the conversation (and to the right subscribers).
        self.session_by_alias = {}
        self.clients = set()
        # Raw hardware state string, not a bool: `gaming` and `undocked`
        # both mean "CPU-only" but differ in everything else, and collapsing
        # them to one flag early is what made this engine blind to undocking
        # in the first place.
        self.hw_state = "docked"

    # -- lifecycle --------------------------------------------------------

    @property
    def gaming(self):
        return self.hw_state == "gaming"

    @property
    def cpu_only(self):
        """True whenever local inference has no GPU to land on.

        Undocked was previously indistinguishable from docked here, so the
        light tier kept running its GPU-tuned tag (`qwen3:4b`) with no eGPU
        present -- Ollama silently fell back to CPU, which works, but skips
        the `qwen3:4b-cpu` tag that exists precisely to pin `num_gpu 0`
        rather than leave it to a fallback.
        """
        return self.hw_state in CPU_ONLY_STATES

    def _read_hw_state(self):
        try:
            with open(HW_STATE_FILE) as f:
                state = json.load(f).get("state")
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            # No state file yet (or a torn write racing ai-workstation's
            # own `> state.json`): assume docked, matching this engine's
            # behaviour before it knew about dock state at all.
            return "docked"
        return state if state in ("docked", "undocked", "gaming") else "docked"

    async def start(self):
        os.makedirs(os.path.dirname(SOCKET_PATH), exist_ok=True)
        # Determine real hardware state BEFORE the first spawn, not just on
        # the next 2s watch-loop tick -- an engine cold-started while
        # already gaming or already undocked (e.g. it crashed and restarted
        # mid-session, or simply booted with the eGPU unplugged) must come
        # up on the cpu tag immediately, not spawn on GPU and then
        # immediately churn a second restart 2s later.
        self.hw_state = self._read_hw_state()
        log(f"hardware state at startup: {self.hw_state}"
            f"{' (CPU-only inference)' if self.cpu_only else ''}")
        t0 = time.monotonic()
        # Warm-up is a DIRECT Ollama call, not a full ACP turn. Confirmed
        # live (Phase 0's finding, reproduced here the first time this
        # engine actually ran): routing warm-up through session/prompt took
        # 54.5s wall time, because it waits for the model to finish
        # *thinking through a whole reply*, not just load into VRAM.
        # Loading weights into VRAM (what warm-up actually needs) is the
        # `prompt eval` phase, which Phase 0's own journalctl evidence
        # showed takes low-single-digit-seconds even cold. A tiny raw
        # /api/generate call gets that without paying for a full reasoning
        # pass -- pins the model via keep_alive exactly the same as a real
        # turn would.
        light_cfg = self.cfg["tiers"]["light"]
        try:
            await self._ollama_warm(light_cfg["cpu_model"] if self.cpu_only else light_cfg["model"],
                                    light_cfg["keep_alive"])
            log(f"light tier model warm in Ollama after {(time.monotonic() - t0) * 1000:.0f}ms")
        except Exception as e:
            log(f"ollama warm-up call failed (non-fatal, first real prompt will just be slower): {e}")
        await self.tiers["light"].ensure_started(cpu_override=self.cpu_only,
                                                 extra_extensions=self._light_extras())
        log(f"light tier fully ready (process+model) in {(time.monotonic() - t0) * 1000:.0f}ms total")
        asyncio.create_task(self._idle_reap_loop())
        asyncio.create_task(self._hw_watch_loop())

    def _light_extras(self):
        """Gaming-only additions to the light tier's extension list.

        Gated on `gaming`, NOT on `cpu_only`: the rationale (Phase 5d) is
        that game questions are usually web questions and a web lookup
        costs the game's own GPU/CPU nothing. Undocked shares the CPU-only
        model tag but none of that reasoning -- and undocked is exactly
        when an extra always-on stdio MCP server is least welcome.
        """
        if self.gaming and self.cfg.get("gaming", {}).get("searxng_on_light"):
            return ["mcp-searxng"]
        return None

    async def _ollama_warm(self, model, keep_alive):
        import urllib.request
        # Ollama's Go-duration parser rejects the bare string "-1" ("time:
        # missing unit in duration") but accepts a JSON *number* -1 for
        # "keep forever" -- confirmed live. Config.json stores "-1" as a
        # string (matching every other keep_alive value, which really are
        # duration strings like "8m"), so normalize just this one case
        # rather than special-casing the schema.
        ka = -1 if keep_alive == "-1" else keep_alive
        # num_predict=1 is the whole point and was missing: this call exists
        # to force the weights resident, which is the load + prompt-eval
        # phase, and the comment above has always said it should happen
        # "without paying for a full reasoning pass" -- but with no cap
        # Ollama generated a complete reply to "hi" every time. On the GPU
        # that is ~2s and invisible. Undocked it is not: qwen3:4b answers
        # "hi" with several hundred tokens of narration at ~6 tok/s, which
        # measured here as 300+ tokens and still going ~50s into engine
        # startup -- i.e. the warm-up call, not the weight load, was the
        # dominant term in undocked startup time. One token proves the
        # model is resident just as well as five hundred do.
        body = json.dumps({"model": model, "prompt": "hi", "stream": False,
                           "keep_alive": ka, "options": {"num_predict": 1}}).encode()
        req = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body,
                                     headers={"Content-Type": "application/json"})

        def _do():
            # Generous relative to the one token it now asks for: the cost
            # here is the cold weight load, and reading ~4GB off disk into
            # RAM undocked is itself tens of seconds. Timing out would only
            # make the first real prompt slower, so err long.
            with urllib.request.urlopen(req, timeout=180) as r:
                r.read()
        await asyncio.get_running_loop().run_in_executor(None, _do)

    async def _new_session_on(self, tier_name):
        r = await self.tiers[tier_name].call("session/new", {"cwd": REPO_ROOT, "mcpServers": []})
        sid = r["result"]["sessionId"]
        sess = Session(sid, tier_name)
        self.sessions[sid] = sess
        self.session_by_alias[sid] = sess
        return sid, r

    def _register_alias(self, sess, tier_name, alias):
        sess.tier_sessions[tier_name] = alias
        self.session_by_alias[alias] = sess

    async def _bind_tier_session(self, sess, tier_name):
        """Ensure `sess` has a goose session on `tier_name`, creating one if
        needed, and return its alias.

        A fresh session/new (rather than session/load of the existing one) is
        the whole point: it is the only way the target tier's own model is
        the one that actually answers -- see Session.tier_sessions.
        """
        existing = sess.tier_sessions.get(tier_name)
        if existing:
            return existing
        tier = self.tiers[tier_name]
        r = await tier.call("session/new", {"cwd": REPO_ROOT, "mcpServers": []}, timeout=300)
        if r.get("error"):
            raise RuntimeError(f"session/new on {tier_name} failed: {r['error']}")
        alias = r["result"]["sessionId"]
        self._register_alias(sess, tier_name, alias)
        log(f"session {sess.id}: new goose session {alias} on tier {tier_name}")
        return alias

    async def _transcript_for(self, alias, limit=40):
        """Recent conversation from goose's own db, for replaying into a
        freshly-created session on another tier.

        Read from sessions.db rather than kept in memory because that is the
        system of record both this engine and Goose Desktop write to, and a
        session may predate this engine process entirely.
        """
        db_path = os.path.expanduser("~/.local/share/goose/sessions/sessions.db")
        try:
            proc = await asyncio.create_subprocess_exec(
                "sqlite3", "-json", db_path,
                "SELECT role, content_json FROM (SELECT id, role, content_json FROM messages "
                f"WHERE session_id = '{alias}' ORDER BY id DESC LIMIT {limit}) ORDER BY id",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await proc.communicate()
            rows = json.loads(out.decode() or "[]")
        except Exception:
            return None
        lines = []
        for row in rows:
            try:
                parts = json.loads(row["content_json"])
            except Exception:
                continue
            if not isinstance(parts, list):
                continue
            body = "".join(p.get("text", "") for p in parts if p.get("type") == "text").strip()
            # Same synthetic scaffolding row SessionSync.qml filters: it is
            # injected context, not anything the human or model said.
            if not body or body.startswith("<turn-context>"):
                continue
            lines.append(f"{'User' if row['role'] == 'user' else 'Assistant'}: {body}")
        if not lines:
            return None
        return "\n".join(lines)

    # -- tier notification handling (routing + escalation interception) --

    async def _on_tier_notification(self, tier_name, obj):
        method = obj.get("method")

        # Tier notifications are stamped with that tier's own goose session
        # alias. Resolve it back to the conversation and rewrite the id in
        # place, so a client that subscribed to session X keeps seeing X no
        # matter which tier is currently answering. Without this rewrite a
        # tier switch would silently orphan every subscriber.
        def _resolve(o):
            raw = o.get("params", {}).get("sessionId")
            s = self.session_by_alias.get(raw) or self.sessions.get(raw)
            if s is not None and raw != s.id:
                o["params"]["sessionId"] = s.id
            return s

        if method == "session/request_permission":
            sess = _resolve(obj)
            await self._broadcast_to_session(sess.id if sess else obj.get("params", {}).get("sessionId"), obj)
            return
        if method != "session/update":
            return
        upd = obj.get("params", {}).get("update", {})
        sess = _resolve(obj)
        sid = sess.id if sess else obj.get("params", {}).get("sessionId")
        kind = upd.get("sessionUpdate")

        if kind == "tool_call":
            tool_name = (upd.get("_meta", {}).get("goose", {}).get("toolCall", {}) or {}).get("toolName") or upd.get("title", "")
            if "escalate" in str(tool_name).lower() and sess is not None:
                raw = upd.get("rawInput") or {}
                reason = raw.get("reason", "the model requested a bigger tier")
                suggested = raw.get("suggested_tier", "heavy_local")
                sess.status = "awaiting_escalation"
                offer = {
                    "jsonrpc": "2.0",
                    "method": "qubi/escalation_offer",
                    "params": {
                        "session": sid,
                        "reason": reason,
                        "suggested_tier": suggested,
                        "options": ["escalate_claude", "escalate_heavy_local", "decline"],
                    },
                }
                await self._broadcast_to_session(sid, offer)
                log(f"session {sid}: escalation offered ({suggested}: {reason!r})")
                # Still forward the raw tool_call so a client-side transcript
                # can show it happened, same as any other tool call.
        if sess is not None:
            if kind in ("agent_message_chunk", "agent_thought_chunk", "tool_call", "tool_call_update"):
                sess.status = "working"
            # Name the sub-step so the indicator can distinguish "still
            # reasoning" from "writing the answer" from "running a tool" --
            # on a local reasoning model those are wildly different waits
            # (measured: 2652 chars of reasoning for a 20-char answer).
            if kind == "agent_thought_chunk":
                sess.phase = "reasoning"
                # Rolling detail derived from text already in hand -- no
                # second inference pass, because summarising the reasoning
                # with another model call would cost more than the turn it
                # describes.
                #
                # Accumulate first, THEN take the tail. Individual chunks are
                # far too small to be meaningful on their own: measured 1511
                # chars arriving as 374 chunks, i.e. ~4 chars each, so using
                # the chunk directly showed the user "Okay". Keeping only a
                # bounded tail of the buffer means this stays O(1) per chunk
                # rather than growing with the reasoning.
                chunk = (upd.get("content") or {}).get("text") or ""
                buf = (getattr(sess, "_reason_buf", "") + chunk)[-600:]
                sess._reason_buf = buf
                # Last sentence-ish fragment that is long enough to read.
                parts = [p.strip() for p in buf.replace("\n", " ").split(". ") if p.strip()]
                tail = next((p for p in reversed(parts) if len(p) > 25), parts[-1] if parts else "")
                if tail:
                    sess.phase_detail = tail[:110]
            elif kind == "agent_message_chunk":
                sess.phase = "responding"
                sess.phase_detail = ""
            elif kind in ("tool_call", "tool_call_update"):
                sess.phase = "tool"
                sess.phase_detail = str(
                    (upd.get("_meta", {}).get("goose", {}).get("toolCall", {}) or {}).get("toolName")
                    or upd.get("title", "")
                )[:110]
            sess.last_activity = time.monotonic()
        await self._broadcast_to_session(sid, obj)

    async def _broadcast_session_created(self, session_id, exclude=None):
        """Announce a newly created session to every other client.

        Deliberately fans out over self.clients rather than a session's
        subscriber set: the whole point is reaching clients that do NOT
        know this session exists yet, so there is nobody subscribed to
        target. A client that cares can follow up with qubi/subscribe.
        """
        sess = self.sessions.get(session_id)
        notif = {
            "jsonrpc": "2.0",
            "method": "qubi/session_created",
            "params": {
                "session": session_id,
                "tier": sess.tier if sess else "light",
            },
        }
        for c in list(self.clients):
            if c is exclude:
                continue
            await c.send(notif)

    async def _broadcast_to_session(self, session_id, obj):
        sess = self.sessions.get(session_id)
        targets = sess.subscribers if sess else self.clients
        for c in list(targets):
            await c.send(obj)
        await self._push_status(session_id)

    async def _push_status(self, session_id):
        sess = self.sessions.get(session_id)
        if not sess:
            return
        notif = {
            "jsonrpc": "2.0",
            "method": "qubi/session_status",
            "params": {
                "session": session_id,
                "status": sess.status,
                # Additive: older clients ignore unknown keys, so this is
                # safe to send unconditionally.
                "phase": getattr(sess, "phase", "idle"),
                "phaseDetail": getattr(sess, "phase_detail", ""),
                "tier": sess.tier,
                "lastActivity": sess.last_activity,
            },
        }
        for c in list(sess.subscribers):
            await c.send(notif)

    async def _set_phase(self, sess, phase, detail=None):
        """Name the current long-running step and tell the client immediately.

        Every call site is a place the engine used to go silent for seconds
        to minutes with no notification at all.
        """
        if sess is None:
            return
        sess.phase = phase
        if detail is not None:
            sess.phase_detail = detail
        await self._push_status(sess.id)

    # -- idle reaping (Phase 7a) + hardware-state watch (Phase 5b) --------

    # How long an ad hoc "use this model now" tier (qubi/use_model) can sit
    # idle before it's torn down. These are meant to be exploratory/
    # throwaway -- clicking through several installed models in the browser
    # should not leave that many resident goose+Ollama processes running
    # forever, which is exactly what would happen with no reaping at all
    # (unlike the named tiers, nothing else ever removes one of these).
    ADHOC_TIER_IDLE_S = 900

    async def _idle_reap_loop(self):
        while True:
            await asyncio.sleep(15)
            for name in ("heavy", "claude"):
                t = self.tiers[name]
                idle_s = self.cfg["tiers"][name].get("idle_timeout_s")
                if t.proc is not None and idle_s and (time.monotonic() - t.last_activity) > idle_s:
                    log(f"{name}: idle {idle_s}s+, reaping")
                    await t.stop()
            for name in [n for n in self.tiers if n not in self.cfg["tiers"]]:
                t = self.tiers[name]
                if t.proc is None or (time.monotonic() - t.last_activity) <= self.ADHOC_TIER_IDLE_S:
                    continue
                log(f"{name}: ad hoc tier idle {self.ADHOC_TIER_IDLE_S}s+, reaping")
                await t.stop()
                del self.tiers[name]
                for sess in self.sessions.values():
                    alias = sess.tier_sessions.pop(name, None)
                    if alias:
                        self.session_by_alias.pop(alias, None)
                    # A session left pointing at a tier that no longer
                    # exists would KeyError on its next prompt -- fall back
                    # to light, the same default a brand-new session gets.
                    if sess.tier == name:
                        sess.tier = "light"

    async def _hw_watch_loop(self):
        while True:
            await asyncio.sleep(2)
            new_state = self._read_hw_state()
            if new_state == self.hw_state:
                continue
            was_cpu_only = self.cpu_only
            was_extras = self._light_extras()
            self.hw_state = new_state
            log(f"hardware state changed -> {new_state}"
                f"{' (CPU-only inference)' if self.cpu_only else ''}")
            # Heavy tier is simply unavailable while gaming (Phase 5b) --
            # reap it now rather than waiting for its idle timer so it
            # can't be holding VRAM/CPU share mid-game. Gated on `gaming`
            # specifically, not on cpu_only: undocked, heavy is slow but
            # still legitimately usable (qwen3-coder:latest on CPU is the
            # documented undocked coding pick, see ai-workstation.nix), so
            # there is nothing to protect it from and no reason to kill it.
            if self.gaming:
                await self.tiers["heavy"].stop()
            # Only bounce the light tier if something it was actually
            # spawned with changed. undocked <-> gaming moves between two
            # CPU-only states where the model tag is identical, so without
            # this check a transition that changes neither the tag nor the
            # extension list would still drop every bound session's process
            # for nothing. Both inputs are compared, not just the tag:
            # undocked -> gaming keeps cpu_only True but does add searxng.
            if self.cpu_only == was_cpu_only and self._light_extras() == was_extras:
                continue
            # Restart the light tier under the new model tag -- any session
            # currently bound to light survives via session/load, same
            # mechanism as a manual tier switch.
            light = self.tiers["light"]
            bound_sessions = [s for s in self.sessions.values() if s.tier == "light"]
            # A dock/undock bounce stops and respawns the light tier under a
            # different model tag while sessions stay bound to it. Previously
            # every bound session just stalled with no notification at all.
            for sess in bound_sessions:
                await self._set_phase(
                    sess, "reloading_hardware",
                    "switching to CPU-only inference" if self.cpu_only else "switching to GPU inference")
            await light.stop()
            await light.ensure_started(cpu_override=self.cpu_only,
                                       extra_extensions=self._light_extras())
            for sess in bound_sessions:
                try:
                    # session/load is correct HERE (unlike a tier switch):
                    # this is the same tier being respawned, so the pinned
                    # model on the session row is the model we want back --
                    # only the process died. Uses the light tier's own alias.
                    await light.call("session/load", {"sessionId": sess.tier_sid("light"), "cwd": REPO_ROOT, "mcpServers": []})
                    await self._set_phase(sess, "idle", "")
                except Exception as e:
                    await self._set_phase(sess, "error", "failed to reload after a hardware change")
                    log(f"session {sess.id}: reload onto {'cpu' if self.cpu_only else 'gpu'} light tier failed: {e}")

    # -- client-facing dispatch --------------------------------------------

    async def handle_client_message(self, client, obj):
        method = obj.get("method")
        if method and method.startswith("qubi/"):
            await self._handle_qubi_method(client, obj)
            return
        await self._handle_acp_method(client, obj)

    async def _handle_qubi_method(self, client, obj):
        method = obj["method"]
        params = obj.get("params", {}) or {}
        req_id = obj.get("id")

        async def reply(result=None, error=None):
            if req_id is None:
                return
            msg = {"jsonrpc": "2.0", "id": req_id}
            msg["error" if error else "result"] = error or result
            await client.send(msg)

        if method == "qubi/status":
            await reply({
                # `gaming` kept for existing clients that read it; `state`
                # and `cpuOnly` are the finer-grained truth (a client that
                # only looks at `gaming` cannot tell undocked from docked,
                # which is exactly the blind spot this engine had).
                "gaming": self.gaming,
                "state": self.hw_state,
                "cpuOnly": self.cpu_only,
                # Filtered to the persistent, named tiers -- self.tiers can
                # also hold ephemeral "model:<tag>" entries from
                # qubi/use_model, and those must never appear in a client's
                # tier-switch dropdown: they exist for one conversation's
                # direct model pick, not as a selectable, reusable tier.
                "tiers": {
                    n: {
                        "running": t.proc is not None and t.proc.returncode is None,
                        "ready": t.ready.is_set(),
                        "starting": t.starting,
                        "model": t.tier_cfg["cpu_model"] if (n == "light" and self.cpu_only) else t.tier_cfg["model"],
                    }
                    for n, t in self.tiers.items()
                    if n in self.cfg["tiers"]
                },
            })
        elif method == "qubi/theme":
            await reply(self._read_theme(params.get("name") or self.cfg.get("theme", "ultraviolet")))
        elif method == "qubi/session_list":
            await reply({"sessions": await self._full_session_list()})
        elif method == "qubi/subscribe":
            sid = params.get("session")
            sess = self.sessions.get(sid)
            if sess is None:
                sess = Session(sid, params.get("tier", "light"))
                self.sessions[sid] = sess
                self.session_by_alias[sid] = sess
            sess.subscribers.add(client)
            client.subscriptions.add(sid)
            await reply({"subscribed": sid})
        elif method == "qubi/set_tier":
            await self._set_tier(client, params.get("session"), params.get("tier"), reply)
        elif method == "qubi/installed_models":
            await reply({"models": await self._installed_models()})
        elif method == "qubi/use_model":
            await self._use_model(params.get("session"), params.get("model"), reply)
        elif method == "qubi/extensions":
            await reply(self._read_extensions())
        elif method == "qubi/session_usage":
            await reply(await self._read_session_usage(params.get("session")))
        else:
            await reply(error={"code": -32601, "message": f"unknown qubi method {method}"})

    async def _installed_models(self):
        """Every model Ollama actually has locally, newest first.

        Straight from Ollama's REST API rather than `ollama list`, so the
        result is structured (size/modified) instead of a text table that
        would need column-parsing.
        """
        def _fetch():
            # Imported locally, matching _ollama_warm: this module's only
            # other urllib use is also function-scoped, and there is no
            # top-level `import urllib.request`.
            import urllib.request
            req = urllib.request.Request("http://127.0.0.1:11434/api/tags")
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read().decode())
        try:
            data = await asyncio.get_running_loop().run_in_executor(None, _fetch)
        except Exception as e:
            log(f"installed_models: {e}")
            return []
        out = []
        for m in data.get("models", []):
            out.append({
                "name": m.get("name") or m.get("model"),
                "sizeBytes": m.get("size") or 0,
                "modifiedAt": m.get("modified_at") or "",
                "parameterSize": (m.get("details") or {}).get("parameter_size") or "",
            })
        out.sort(key=lambda m: m["modifiedAt"], reverse=True)
        return out

    async def _use_model(self, session_id, model, reply):
        """Switch ONE conversation onto a specific local model, right now,
        without touching any tier's persistent configuration.

        This is deliberately NOT the same operation as reassigning a named
        tier's model (that used to be `qubi/set_tier_model`, since removed):
        clicking a model in the browser's "use it now" flow must not mutate
        ~/.config/qubi/config.json or change what `light`/`fast`/`heavy`
        mean for every other session -- it should just answer the CURRENT
        conversation with the chosen model, same idea as picking a tier from
        the dropdown, except keyed by an exact model tag instead of a
        pre-configured tier name.

        Implemented as a synthetic, in-memory-only tier named `model:<tag>`,
        created on first use and reused by any session that picks the same
        model again. It never enters self.cfg["tiers"] and is therefore
        invisible to qubi_config.save(), to qubi/status's tier list (see the
        `n in self.cfg["tiers"]` filter there), and to a restart -- exactly
        the "ephemeral, not a replacement" behaviour asked for. Everything
        else (context replay across the switch, per-tier goose sessions so
        the right model actually answers, idle reaping) is the exact same
        generic machinery _switch_tier/_bind_tier_session already give every
        real tier -- see Session.tier_sessions' own header comment for why a
        fresh session/new per tier is required at all.
        """
        sess = self.sessions.get(session_id)
        if sess is None:
            await reply(error={"code": -32602, "message": f"unknown session {session_id}"})
            return
        if not model:
            await reply(error={"code": -32602, "message": "model is required"})
            return
        installed = {m["name"] for m in await self._installed_models()}
        if installed and model not in installed:
            await reply(error={"code": -32602, "message": f"{model} is not installed in Ollama"})
            return

        tier_key = f"model:{model}"
        if tier_key not in self.tiers:
            # No extensions: this path is for "answer me directly with this
            # model", not a tool-using session -- same reasoning as `fast`.
            self.tiers[tier_key] = TierProcess(tier_key, {
                "provider": "ollama",
                "model": model,
                "cpu_model": model,
                "extensions": [],
                "keep_alive": "-1",
                "warm_at_start": False,
                "idle_timeout_s": None,
                "no_think_prefix": False,
            }, self._on_tier_notification)

        await self.tiers[tier_key].ensure_started()
        old_tier = sess.tier
        try:
            await self._switch_tier(sess, tier_key)
        except Exception as e:
            await reply(error={"code": -32000, "message": f"switch to {model} failed: {e}"})
            return
        sess.status = "idle"
        await self._set_phase(sess, "idle", "")
        log(f"session {session_id}: using {model} directly (was {old_tier})")
        await reply({"session": session_id, "model": model})

    def _read_extensions(self):
        """Enabled-extension count + names, straight from goose's own
        config.yaml. Exists because a browser client (mobile_gui.html) has
        no filesystem access to read this the way the desktop QML client
        does (a direct `yq`/`cat` Process) -- this engine runs on the same
        host as the config file, so it can just read it and answer over
        the wire. Reuses the real yaml.safe_load already required for
        _read_theme-adjacent config reading (not JSON.parse/cat, which
        broke once before -- see qubi_engine.py's own history) rather than
        adding a second parsing path.
        """
        try:
            with open(BASE_GOOSE_CONFIG) as f:
                cfg = yaml.safe_load(f) or {}
        except (FileNotFoundError, yaml.YAMLError):
            return {"enabledCount": 0, "extensions": []}
        extensions = cfg.get("extensions") or {}
        enabled = [
            {"key": k, "name": e.get("display_name") or e.get("name") or k}
            for k, e in extensions.items() if isinstance(e, dict) and e.get("enabled") is True
        ]
        enabled.sort(key=lambda e: e["name"])
        return {"enabledCount": len(enabled), "extensions": enabled}

    async def _read_session_usage(self, session_id):
        """total_tokens/accumulated_total_tokens for a session, straight
        from goose's sessions.db. Only needed for the INITIAL number on a
        resumed session -- session/load's own result carries no usage
        field (confirmed live), unlike session/prompt's result, which
        already includes real usage data per turn and needs no help here.
        Same sqlite3 -json subprocess pattern _full_session_list already
        uses, just a single narrower query.
        """
        if not session_id:
            return {"totalTokens": 0, "accumulatedTotalTokens": 0}
        # Sum across every tier's goose session for this conversation, not
        # just the original id. Once a conversation switches tiers, the new
        # tier's tokens accrue against ITS session row, so querying only the
        # client-facing id would freeze the counter at whatever it read
        # before the switch.
        sess = self.sessions.get(session_id)
        ids = sorted(set(sess.tier_sessions.values())) if sess else [session_id]
        id_list = ", ".join(f"'{i}'" for i in ids)
        db_path = os.path.expanduser("~/.local/share/goose/sessions/sessions.db")
        try:
            proc = await asyncio.create_subprocess_exec(
                "sqlite3", "-json", db_path,
                f"SELECT COALESCE(SUM(total_tokens), 0) AS totalTokens, "
                f"COALESCE(SUM(accumulated_total_tokens), 0) AS accumulatedTotalTokens "
                f"FROM sessions WHERE id IN ({id_list})",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await proc.communicate()
            rows = json.loads(out.decode() or "[]")
        except Exception:
            rows = []
        return rows[0] if rows else {"totalTokens": 0, "accumulatedTotalTokens": 0}

    def _read_theme(self, name):
        theme_dir = os.path.join(REPO_ROOT, "themes", name)
        tokens = {"name": name}
        b16_path = os.path.join(theme_dir, "base16.yaml")
        manifest_path = os.path.join(theme_dir, "theme.json")
        if os.path.exists(b16_path):
            # base16.yaml in this repo is plain `key: "hex"  # trailing
            # comment` lines (no nested structure, no leading "#" on the
            # hex itself) -- confirmed by reading the real file. A tiny
            # line parser avoids pulling in a YAML dependency for one flat
            # key:value file, but has to extract the *quoted* value
            # specifically rather than just splitting on ":" -- every real
            # line here has a trailing `# role description` comment, and a
            # bare .strip('"') only strips a quote character sitting at
            # the very start/end of the whole remainder, so it silently
            # left the comment text glued onto the value (confirmed live:
            # a mobile_gui.html theme application rendered a literal
            # `#050505"   # app background` as a CSS color before this
            # fix) instead of raising -- the exact kind of bug this
            # session's own discipline is to catch by testing live rather
            # than trusting a function compiled without error.
            base16 = {}
            with open(b16_path) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or ":" not in line:
                        continue
                    k, _, rest = line.partition(":")
                    m = re.search(r'"([^"]*)"', rest) or re.search(r"'([^']*)'", rest)
                    if m:
                        base16[k.strip()] = m.group(1)
            tokens["base16"] = base16
        if os.path.exists(manifest_path):
            with open(manifest_path) as f:
                tokens["manifest"] = json.load(f)
        return tokens

    async def _full_session_list(self):
        """Combines the engine's own live-known sessions with everything
        in Goose's SQLite that the engine didn't create (terminal `goose
        run`/`qubi-code` runs) -- Phase 2d's "complete even if some sessions
        bypass it" requirement."""
        live = {sid: {"session": sid, "tier": s.tier, "status": s.status, "live": True}
                for sid, s in self.sessions.items()}
        db_path = os.path.expanduser("~/.local/share/goose/sessions/sessions.db")
        try:
            proc = await asyncio.create_subprocess_exec(
                "sqlite3", "-json", db_path,
                "SELECT id, working_dir, updated_at, goose_mode FROM sessions ORDER BY updated_at DESC LIMIT 50",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await proc.communicate()
            rows = json.loads(out.decode() or "[]")
        except Exception:
            rows = []
        for row in rows:
            sid = row["id"]
            if sid in live:
                continue
            live[sid] = {"session": sid, "tier": None, "status": "done", "live": False,
                        "workingDir": row.get("working_dir"), "updatedAt": row.get("updated_at")}
        return list(live.values())

    async def _switch_tier(self, sess, target_tier):
        """Move a conversation onto another tier.

        Binds (creating if necessary) a goose session on the target tier and
        queues the prior conversation for replay. Deliberately NOT
        session/load of the existing session: goose pins the model onto the
        session row at creation, so loading the old session onto a new tier
        keeps the OLD model answering -- which is why the `fast` tier was
        still running qwen3 despite every config key saying llama3.2.

        Re-entering a tier reuses that tier's existing goose session, so
        bouncing light -> heavy -> light does not spawn a session each time
        and the model still has its own side of the conversation.
        """
        previous_alias = sess.tier_sid()
        was_new = target_tier not in sess.tier_sessions
        await self._bind_tier_session(sess, target_tier)
        if was_new and previous_alias:
            # Fresh session on that tier => no memory of this conversation.
            sess.pending_context = await self._transcript_for(previous_alias)
        sess.tier = target_tier

    async def _set_tier(self, client, session_id, target_tier, reply):
        sess = self.sessions.get(session_id)
        if sess is None:
            await reply(error={"code": -32602, "message": f"unknown session {session_id}"})
            return
        if target_tier not in self.tiers:
            await reply(error={"code": -32602, "message": f"unknown tier {target_tier}"})
            return
        target = self.tiers[target_tier]
        # Another silent gap: switching to a cold tier loads a model that can
        # take minutes, and the client previously got nothing until the reply
        # at the end of this function.
        await self._set_phase(sess, "switching_tier",
                              f"starting the {target_tier} tier "
                              f"({target.tier_cfg.get('model', '?')})")
        await target.ensure_started(cpu_override=(target_tier == "light" and self.cpu_only),
                                    extra_extensions=self._light_extras() if target_tier == "light" else None)
        old_tier = sess.tier
        try:
            await self._switch_tier(sess, target_tier)
        except Exception as e:
            await self._set_phase(sess, "error", "")
            await reply(error={"code": -32000, "message": f"switch to {target_tier} failed: {e}"})
            return
        sess.status = "idle"
        await self._set_phase(sess, "idle", "")
        log(f"session {session_id}: switched {old_tier} -> {target_tier}")
        await reply({"session": session_id, "tier": target_tier})
        if sess.last_user_prompt is not None:
            log(f"session {session_id}: re-sending last prompt to {target_tier}")
            await self._dispatch_prompt(sess, sess.last_user_prompt, client)

    async def _handle_acp_method(self, client, obj):
        method = obj.get("method")
        req_id = obj.get("id")
        params = obj.get("params", {}) or {}

        # Response to an agent-initiated request the client is answering
        # (session/request_permission) -- these carry no "method", just
        # id+result, so route by which session's tier issued that id...
        # simplification: for a permission response we forward to every
        # tier that has this session bound (there's exactly one), keyed by
        # session param the client should have echoed back. GooseAcpSession
        # .qml sends {id, result:{outcome:...}} with no sessionId in the
        # payload (see respondToPermission) -- so route using the session
        # currently subscribed for this client as the disambiguator.
        if method is None and ("result" in obj or "error" in obj):
            sid = next(iter(client.subscriptions), None)
            sess = self.sessions.get(sid) if sid else None
            if sess:
                self.tiers[sess.tier].send_raw(obj)
            return

        if method == "initialize":
            await client.send({"jsonrpc": "2.0", "id": req_id, "result": {
                "protocolVersion": 1,
                "agentCapabilities": {"loadSession": True},
                "agentInfo": {"name": "qubi-engine", "version": "1.0.0"},
            }})
            return

        if method == "session/new":
            sid, r = await self._new_session_on("light")
            client.subscriptions.add(sid)
            self.sessions[sid].subscribers.add(client)
            await client.send({"jsonrpc": "2.0", "id": req_id, "result": r["result"]})
            # Tell every OTHER connected client a session now exists.
            # Nothing else in the engine ever announces this -- broadcasts
            # are strictly subscriber-scoped and a brand-new session has
            # exactly one subscriber, so before this a second client could
            # only discover it by polling qubi/session_list.
            await self._broadcast_session_created(sid, exclude=client)
            return

        if method == "session/prompt":
            sid = params.get("sessionId")
            text = "".join(p.get("text", "") for p in params.get("prompt", []) if p.get("type") == "text")
            sess = self.sessions.get(sid)
            if sess is None:
                await client.send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32602, "message": "unknown session"}})
                return
            sess.last_user_prompt = text
            sess.subscribers.add(client)
            client.subscriptions.add(sid)
            await self._dispatch_prompt(sess, text, client, req_id=req_id)
            return

        # Every other ACP method (session/list, session/set_mode,
        # session/cancel, session/load, ...) forwards verbatim to whichever
        # tier the target session (if any) is bound to, defaulting to
        # light -- this is the "unchanged protocol" contract.
        sid = params.get("sessionId")
        sess = self.sessions.get(sid)
        tier_name = sess.tier if sess else "light"
        # Translate the client-facing id to the current tier's own goose
        # session alias. For a session that has never switched tiers these
        # are identical, so this is a no-op on the common path; after a
        # switch it is what keeps session/cancel, session/set_mode etc.
        # addressing the session the tier actually has open.
        if sess is not None and sess.tier_sid() != sid:
            params = dict(params)
            params["sessionId"] = sess.tier_sid()
        try:
            r = await self.tiers[tier_name].call(method, params)
            # session/load resumes a session the engine may know nothing
            # about (a DB row from a terminal run, or from before a
            # restart). Registering the caller as a subscriber here is
            # what makes a RESUMED session push notifications at all --
            # without it the client got nothing until it happened to send
            # its own first prompt, because only session/new and
            # session/prompt ever added a subscriber. Vivify a Session for
            # the id if needed, exactly as qubi/subscribe already does.
            if method == "session/load" and sid and not r.get("error"):
                if sess is None:
                    sess = Session(sid, tier_name)
                    self.sessions[sid] = sess
                    self.session_by_alias[sid] = sess
                sess.subscribers.add(client)
                client.subscriptions.add(sid)
                log(f"session {sid}: client subscribed via session/load")
            await client.send({"jsonrpc": "2.0", "id": req_id, "result": r.get("result"), "error": r.get("error")} if r.get("error") else {"jsonrpc": "2.0", "id": req_id, "result": r.get("result")})
        except Exception as e:
            await client.send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32000, "message": str(e)}})

    async def _dispatch_prompt(self, sess, text, client, req_id=None):
        # Route on the very first prompt only -- once a session has a real
        # tier bound (light by construction, or escalated), it stays there
        # until an explicit qubi/set_tier.
        if not getattr(sess, "_routed", False):
            tier_choice, score, reasons = score_prompt(text)
            sess._routed = True
            log(f"session {sess.id}: routed -> {tier_choice} (score={score}, {reasons})")
            if tier_choice == "heavy" and sess.tier != "heavy":
                # The worst silent gap in the whole engine: a cold heavy tier
                # means spawning `goose acp`, an initialize handshake and
                # loading a multi-GB model, all before the prompt is even
                # sent. Announce it instead of letting the panel sit blank.
                heavy_model = self.tiers["heavy"].tier_cfg.get("model", "heavy model")
                await self._set_phase(sess, "starting_model",
                                      f"loading {heavy_model} for a heavier request")
                await self.tiers["heavy"].ensure_started()
                # session/new on heavy, not session/load of the light
                # session -- loading would restore light's pinned model and
                # the "heavy" tier would answer as qwen3:4b.
                await self._switch_tier(sess, "heavy")

        if sess.busy:
            fut = asyncio.get_running_loop().create_future()
            sess.prompt_queue.append((client, text, req_id, fut))
            # Was "awaiting_permission", which is what a real permission
            # prompt uses -- a queued turn rendered as "awaiting permission"
            # in any UI that showed status verbatim. It is a queue, say so.
            sess.status = "queued"
            await self._set_phase(sess, "queued",
                                  "waiting for the current reply to finish")
            return await fut

        sess.busy = True
        sess.status = "working"
        sess.phase_detail = ""
        sess._reason_buf = ""
        await self._set_phase(sess, "thinking", "")
        # The alias can legitimately be missing here: a fresh ad hoc
        # "model:<tag>" tier from qubi/use_model has no session yet.
        # Rebinding lazily (rather than eagerly at switch time) means the
        # cost is paid on the next prompt, not on a settings click.
        if sess.tier not in sess.tier_sessions:
            await self.tiers[sess.tier].ensure_started(
                cpu_override=(sess.tier == "light" and self.cpu_only),
                extra_extensions=self._light_extras() if sess.tier == "light" else None)
            await self._bind_tier_session(sess, sess.tier)
        # Per-tier reasoning suppression. qwen3 narrates its reasoning as
        # ordinary content no matter what: GOOSE_LOCAL_ENABLE_THINKING=false
        # and Ollama's own think:false were both measured to only move that
        # text out of the `thinking` field and into the visible answer, and
        # neither makes the turn shorter. `/no_think` is the one switch that
        # measurably cuts generation (196 -> 104 tokens on the same prompt).
        # It is a property of the TIER, not a global: the fast tier wants it,
        # the heavy tier must never get it.
        #
        # Applied here, at the last moment before dispatch, because this is
        # the only place the outgoing prompt is built -- session/prompt is
        # the one ACP method the engine rebuilds from scratch rather than
        # forwarding verbatim, so anything a client attaches upstream is
        # discarded before it reaches this point.
        outgoing = text
        if self.tiers[sess.tier].tier_cfg.get("no_think_prefix"):
            outgoing = f"/no_think {text}"
        # First prompt after a tier switch: the target tier's goose session
        # is brand new and therefore has no memory of the conversation, so
        # replay it as a preamble. Consumed once.
        if sess.pending_context:
            # Fenced and explicitly labelled as reference material. An
            # earlier, looser wording ("here is the conversation so far …
            # continue it") made the model continue the *transcript* rather
            # than answer: a follow-up came back as "OKteal", echoing the
            # previous turn's "OK" before its actual answer.
            outgoing = (
                "[context from earlier in this conversation, handled by a different model]\n"
                "<<<TRANSCRIPT\n"
                f"{sess.pending_context}\n"
                "TRANSCRIPT>>>\n"
                "That transcript is background only -- do not repeat, quote or continue it.\n"
                f"Answer only this new message from the user:\n{outgoing}"
            )
            sess.pending_context = None
        try:
            r = await self.tiers[sess.tier].call("session/prompt", {
                "sessionId": sess.tier_sid(),
                "prompt": [{"type": "text", "text": outgoing}],
            }, timeout=300)
        except Exception as e:
            r = {"error": {"code": -32000, "message": str(e)}}
        sess.busy = False
        sess.status = "done" if "error" not in r else "error"
        await self._set_phase(sess, "done" if "error" not in r else "error", "")
        if req_id is not None:
            reply = {"jsonrpc": "2.0", "id": req_id}
            reply["error" if "error" in r else "result"] = r.get("error") or r.get("result")
            await client.send(reply)
        if sess.prompt_queue:
            next_client, next_text, next_req_id, next_fut = sess.prompt_queue.pop(0)
            asyncio.create_task(self._dispatch_prompt(sess, next_text, next_client, req_id=next_req_id))
            next_fut.set_result(None)
        return r

    # -- transports ---------------------------------------------------------

    async def serve_socket(self):
        try:
            os.unlink(SOCKET_PATH)
        except FileNotFoundError:
            pass

        async def handle(reader, writer):
            client = ClientConn("socket", writer)
            self.clients.add(client)
            log(f"socket client connected ({len(self.clients)} total)")
            try:
                while True:
                    line = await reader.readline()
                    if not line:
                        break
                    s = line.decode(errors="replace").strip()
                    if not s:
                        continue
                    try:
                        obj = json.loads(s)
                    except json.JSONDecodeError:
                        continue
                    await self.handle_client_message(client, obj)
            except (ConnectionResetError, BrokenPipeError):
                pass
            finally:
                self.clients.discard(client)
                for sid in client.subscriptions:
                    sess = self.sessions.get(sid)
                    if sess:
                        sess.subscribers.discard(client)
                log(f"socket client disconnected ({len(self.clients)} total)")

        server = await asyncio.start_unix_server(handle, path=SOCKET_PATH)
        log(f"listening on unix socket {SOCKET_PATH}")
        return server

    async def serve_ws(self, host, port):
        async def handle(ws):
            client = ClientConn("ws", ws)
            self.clients.add(client)
            log(f"ws client connected ({len(self.clients)} total)")
            try:
                async for msg in ws:
                    for line in msg.splitlines():
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        await self.handle_client_message(client, obj)
            except ConnectionClosed:
                pass
            finally:
                self.clients.discard(client)
                for sid in client.subscriptions:
                    sess = self.sessions.get(sid)
                    if sess:
                        sess.subscribers.discard(client)
                log(f"ws client disconnected ({len(self.clients)} total)")

        log(f"listening on ws://{host}:{port}")
        return await websockets.serve(handle, host, port)


async def main():
    cfg = qubi_config.load()
    engine = Engine(cfg)
    await engine.start()
    await engine.serve_socket()
    await engine.serve_ws(cfg["engine"]["ws_host"], cfg["engine"]["ws_port"])
    await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
