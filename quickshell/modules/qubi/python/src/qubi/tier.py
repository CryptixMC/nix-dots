"""One tier = one `goose acp` subprocess with its own isolated goose config."""
import asyncio
import json
import os
import shutil
import sys
import time

import yaml

from . import paths
from ._log import log


def escalate_command():
    """argv for the escalate MCP server (qubi.mcp.escalate).

    Resolved rather than hardcoded so the tier always launches the copy that
    shipped with THIS engine: the console script installed next to the
    running entry point first, then PATH, then the module under the current
    interpreter (a source checkout run with `python -m qubi.engine`).
    """
    override = os.environ.get("QUBI_ESCALATE_CMD")
    if override:
        return override.split()
    sibling = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "qubi-escalate-mcp")
    if os.access(sibling, os.X_OK):
        return [sibling]
    found = shutil.which("qubi-escalate-mcp")
    if found:
        return [found]
    return [sys.executable, "-m", "qubi.mcp.escalate"]


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
    with open(paths.BASE_GOOSE_CONFIG) as f:
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
        escalate_argv = escalate_command()
        exts["escalate"] = {
            "bundled": False,
            "cmd": escalate_argv[0],
            "description": "Escalate to a bigger model instead of guessing",
            "display_name": "Escalate",
            "enabled": True,
            "name": "escalate",
            "timeout": 30,
            "type": "stdio",
            # Goose's stdio extension launcher takes cmd+args as a single
            # exec vector. See escalate_command for how it is resolved.
            "args": escalate_argv[1:],
        }
    cfg["extensions"] = exts

    # Rewrite the model/provider keys to THIS tier's, not the base config's.
    #
    # Without this the tier config is a verbatim copy of
    # ~/.config/goose/config.yaml apart from `extensions`, so every tier
    # inherited that file's model (qwen3:4b) no matter what the tier asked
    # for. The GOOSE_MODEL env var set in ensure_started does not reliably
    # win over the config file, which is exactly the leak docs/history/BLOCKERS-2026-09-19.md
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

    tier_dir = os.path.join(paths.TIERCONF_DIR, tier_name, "goose")
    os.makedirs(tier_dir, exist_ok=True)
    with open(os.path.join(tier_dir, "config.yaml"), "w") as f:
        json.dump(cfg, f)
    return os.path.join(paths.TIERCONF_DIR, tier_name)


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

