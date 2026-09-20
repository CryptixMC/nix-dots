#!/usr/bin/env python3
"""qubi-engine: one persistent daemon, many clients, per-turn tier routing.

One shared `goose acp` process per tier, fanned out to every subscriber, in
front of a router that still speaks bare ACP JSON-RPC to every client -- a
client that used to spawn `goose acp` directly only needs its transport
swapped (socket instead of stdio); every method/id/notification it already
understands still means exactly the same thing on the other side of this
daemon. See docs/protocol.md.

Transports:
  - $XDG_RUNTIME_DIR/qubi/engine.sock (Unix socket) -- desktop clients.
  - 127.0.0.1:8765 (WebSocket) -- mobile, behind e.g. tailscale serve.
Both carry the identical message shape: one JSON object per line/frame,
either a real ACP JSON-RPC message (forwarded to/from a tier's `goose acp`
process, request ids remapped so concurrent clients can't collide) or a
`qubi/*`-namespaced engine method (handled here, never forwarded).

The Engine class is only the composition root. Each concern lives in its own
module as a mixin over the shared state set up in __init__:
  tier.py       TierProcess + per-tier goose config generation
  sessions.py   Session, per-tier aliases, transcript replay, sessions.db reads
  routing.py    score_prompt + the per-session prompt queue/dispatch
  notify.py     tier notification rewriting, escalation offers, status pushes
  hw.py         docked/undocked/gaming state and the light-tier bounce
  ollama.py     direct Ollama REST calls
  rpc.py        the qubi/* method table
  acp_proxy.py  ACP passthrough
  transport.py  unix socket + websocket servers
"""
import asyncio
import time

from . import config as qubi_config
from . import paths
from ._log import log
from .acp_proxy import AcpProxyMixin
from .hw import HwMixin
from .notify import NotifyMixin
from .ollama import OllamaMixin
from .routing import RoutingMixin
from .rpc import QubiMethodsMixin
from .sessions import SessionsMixin
from .tier import TierProcess
from .transport import TransportMixin


class Engine(HwMixin, OllamaMixin, SessionsMixin, NotifyMixin, QubiMethodsMixin,
             AcpProxyMixin, RoutingMixin, TransportMixin):
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
    async def start(self):
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

    # -- client-facing dispatch --------------------------------------------

    async def handle_client_message(self, client, obj):
        method = obj.get("method")
        if method and method.startswith("qubi/"):
            await self._handle_qubi_method(client, obj)
            return
        await self._handle_acp_method(client, obj)


async def amain():
    cfg = qubi_config.load()
    engine = Engine(cfg)
    await engine.start()
    await engine.serve_socket()
    ws_enabled, ws_host, ws_port = paths.ws_bind(cfg)
    if ws_enabled:
        await engine.serve_ws(ws_host, ws_port)
    await asyncio.Future()


def main():
    asyncio.run(amain())


if __name__ == "__main__":
    main()
