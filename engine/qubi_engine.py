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

GAMING_STATE_FILE = "/run/ai-workstation/state.json"


def log(*a):
    print("[qubi-engine]", *a, flush=True)


# --------------------------------------------------------------------------
# Per-tier goose config generation
# --------------------------------------------------------------------------

def build_tier_config_dir(tier_name, tier_cfg, extra_extensions=None):
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

    async def ensure_started(self, cpu_override=False, extra_extensions=None):
        if self.proc is not None and self.proc.returncode is None:
            return
        self.starting = True
        self.ready.clear()
        model = self.tier_cfg["cpu_model"] if cpu_override else self.tier_cfg["model"]
        config_home = build_tier_config_dir(self.name, self.tier_cfg, extra_extensions=extra_extensions)
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
        env["GOOSE_MAX_TOKENS"] = "4096"
        log(f"{self.name}: spawning goose acp (provider={self.tier_cfg['provider']} model={model or '(default)'})")
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
        self.last_activity = time.monotonic()
        self.subscribers = set()  # ClientConn set
        self.last_user_prompt = None
        self.prompt_queue = []  # (ClientConn, params, respond_future)
        self.busy = False


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
        for name in ("light", "heavy", "claude"):
            self.tiers[name] = TierProcess(name, cfg["tiers"][name], self._on_tier_notification)
        self.sessions = {}  # session_id -> Session
        self.clients = set()
        self.gaming = False

    # -- lifecycle --------------------------------------------------------

    def _read_gaming_state(self):
        try:
            with open(GAMING_STATE_FILE) as f:
                return json.load(f).get("state") == "gaming"
        except (FileNotFoundError, json.JSONDecodeError):
            return False

    async def start(self):
        os.makedirs(os.path.dirname(SOCKET_PATH), exist_ok=True)
        # Determine real gaming state BEFORE the first spawn, not just on
        # the next 2s watch-loop tick -- an engine cold-started while
        # already gaming (e.g. engine crashed and restarted mid-session)
        # must come up on the cpu tag immediately, not spawn on GPU and
        # then immediately churn a second restart 2s later.
        self.gaming = self._read_gaming_state()
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
            await self._ollama_warm(light_cfg["cpu_model"] if self.gaming else light_cfg["model"],
                                    light_cfg["keep_alive"])
            log(f"light tier model warm in Ollama after {(time.monotonic() - t0) * 1000:.0f}ms")
        except Exception as e:
            log(f"ollama warm-up call failed (non-fatal, first real prompt will just be slower): {e}")
        gaming_extras = ["mcp-searxng"] if (self.gaming and self.cfg.get("gaming", {}).get("searxng_on_light")) else None
        await self.tiers["light"].ensure_started(cpu_override=self.gaming, extra_extensions=gaming_extras)
        log(f"light tier fully ready (process+model) in {(time.monotonic() - t0) * 1000:.0f}ms total")
        asyncio.create_task(self._idle_reap_loop())
        asyncio.create_task(self._gaming_watch_loop())

    async def _ollama_warm(self, model, keep_alive):
        import urllib.request
        # Ollama's Go-duration parser rejects the bare string "-1" ("time:
        # missing unit in duration") but accepts a JSON *number* -1 for
        # "keep forever" -- confirmed live. Config.json stores "-1" as a
        # string (matching every other keep_alive value, which really are
        # duration strings like "8m"), so normalize just this one case
        # rather than special-casing the schema.
        ka = -1 if keep_alive == "-1" else keep_alive
        body = json.dumps({"model": model, "prompt": "hi", "stream": False,
                           "keep_alive": ka}).encode()
        req = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body,
                                     headers={"Content-Type": "application/json"})

        def _do():
            with urllib.request.urlopen(req, timeout=60) as r:
                r.read()
        await asyncio.get_running_loop().run_in_executor(None, _do)

    async def _new_session_on(self, tier_name):
        r = await self.tiers[tier_name].call("session/new", {"cwd": REPO_ROOT, "mcpServers": []})
        sid = r["result"]["sessionId"]
        self.sessions[sid] = Session(sid, tier_name)
        return sid, r

    # -- tier notification handling (routing + escalation interception) --

    async def _on_tier_notification(self, tier_name, obj):
        method = obj.get("method")
        if method == "session/request_permission":
            sid = obj.get("params", {}).get("sessionId")
            await self._broadcast_to_session(sid, obj)
            return
        if method != "session/update":
            return
        upd = obj.get("params", {}).get("update", {})
        sid = obj.get("params", {}).get("sessionId")
        sess = self.sessions.get(sid)
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
                "tier": sess.tier,
                "lastActivity": sess.last_activity,
            },
        }
        for c in list(sess.subscribers):
            await c.send(notif)

    # -- idle reaping (Phase 7a) + gaming watch (Phase 5b) ----------------

    async def _idle_reap_loop(self):
        while True:
            await asyncio.sleep(15)
            for name in ("heavy", "claude"):
                t = self.tiers[name]
                idle_s = self.cfg["tiers"][name].get("idle_timeout_s")
                if t.proc is not None and idle_s and (time.monotonic() - t.last_activity) > idle_s:
                    log(f"{name}: idle {idle_s}s+, reaping")
                    await t.stop()

    async def _gaming_watch_loop(self):
        while True:
            await asyncio.sleep(2)
            now_gaming = self._read_gaming_state()
            if now_gaming == self.gaming:
                continue
            self.gaming = now_gaming
            log(f"gaming state changed -> {'GAMING (CPU only)' if now_gaming else 'normal'}")
            # Heavy tier is simply unavailable while gaming (Phase 5b) --
            # reap it now rather than waiting for its idle timer so it
            # can't be holding VRAM/CPU share mid-game.
            if now_gaming:
                await self.tiers["heavy"].stop()
            # Restart the light tier under the new model (cpu tag while
            # gaming, normal GPU tag otherwise) -- any session currently
            # bound to light survives via session/load, same mechanism as
            # a manual tier switch. While gaming, light also gets searxng
            # (Phase 5d): game questions are usually web questions, and a
            # web lookup costs the game's own GPU/CPU nothing.
            light = self.tiers["light"]
            bound_sessions = [s for s in self.sessions.values() if s.tier == "light"]
            await light.stop()
            gaming_extras = ["mcp-searxng"] if (now_gaming and self.cfg.get("gaming", {}).get("searxng_on_light")) else None
            await light.ensure_started(cpu_override=now_gaming, extra_extensions=gaming_extras)
            for sess in bound_sessions:
                try:
                    await light.call("session/load", {"sessionId": sess.id, "cwd": REPO_ROOT, "mcpServers": []})
                except Exception as e:
                    log(f"session {sess.id}: reload onto {'cpu' if now_gaming else 'gpu'} light tier failed: {e}")

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
                "gaming": self.gaming,
                "tiers": {
                    n: {
                        "running": t.proc is not None and t.proc.returncode is None,
                        "ready": t.ready.is_set(),
                        "starting": t.starting,
                        "model": t.tier_cfg["cpu_model"] if (n == "light" and self.gaming) else t.tier_cfg["model"],
                    }
                    for n, t in self.tiers.items()
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
            sess.subscribers.add(client)
            client.subscriptions.add(sid)
            await reply({"subscribed": sid})
        elif method == "qubi/set_tier":
            await self._set_tier(client, params.get("session"), params.get("tier"), reply)
        else:
            await reply(error={"code": -32601, "message": f"unknown qubi method {method}"})

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

    async def _set_tier(self, client, session_id, target_tier, reply):
        sess = self.sessions.get(session_id)
        if sess is None:
            await reply(error={"code": -32602, "message": f"unknown session {session_id}"})
            return
        if target_tier not in self.tiers:
            await reply(error={"code": -32602, "message": f"unknown tier {target_tier}"})
            return
        target = self.tiers[target_tier]
        await target.ensure_started(cpu_override=(target_tier == "light" and self.gaming))
        try:
            await target.call("session/load", {"sessionId": session_id, "cwd": REPO_ROOT, "mcpServers": []})
        except Exception as e:
            await reply(error={"code": -32000, "message": f"session/load on {target_tier} failed: {e}"})
            return
        old_tier = sess.tier
        sess.tier = target_tier
        sess.status = "idle"
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
                await self.tiers["heavy"].ensure_started()
                await self.tiers["heavy"].call("session/load", {"sessionId": sess.id, "cwd": REPO_ROOT, "mcpServers": []})
                sess.tier = "heavy"

        if sess.busy:
            fut = asyncio.get_running_loop().create_future()
            sess.prompt_queue.append((client, text, req_id, fut))
            sess.status = "awaiting_permission"  # queued behind another driver
            await self._push_status(sess.id)
            return await fut

        sess.busy = True
        sess.status = "working"
        await self._push_status(sess.id)
        try:
            r = await self.tiers[sess.tier].call("session/prompt", {
                "sessionId": sess.id,
                "prompt": [{"type": "text", "text": text}],
            }, timeout=300)
        except Exception as e:
            r = {"error": {"code": -32000, "message": str(e)}}
        sess.busy = False
        sess.status = "done" if "error" not in r else "error"
        await self._push_status(sess.id)
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
