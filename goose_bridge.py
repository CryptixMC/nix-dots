"""WebSocket -> goose acp relay bridge, fanned out to multiple subscribers.

v2: was previously a dumb per-client relay (one `goose acp` subprocess per
WebSocket connection) -- correct for a single phone, but meant a second
phone (or the phone at all, relative to the desktop) could never see a
session another client was already driving, since each connection got its
own fully independent process and session from a cold start. This version
holds exactly ONE `goose acp` process for the bridge's entire lifetime and
fans its stdout out to every currently-connected client, so N simultaneous
phone clients are all genuinely subscribed to the same live session and
see the same stream. Still a dumb relay otherwise -- no ACP parsing here,
`mobile_gui.html` speaks the real protocol directly, same as before.

Does NOT unify with the desktop chat overlay's own `goose acp` process
(GooseAcpSession.qml) -- that stays a fully separate process with its own
separate session, deliberately. Investigated `goose serve` (the native
ACP-over-HTTP surface) as a possible shared backend both could point at;
confirmed it exists and is real (POST to enqueue a JSON-RPC message + GET
with `Accept: text/event-stream` and a matching `Acp-Connection-Id` header
to receive results/notifications -- confirmed live, not from docs), but
found no evidence of a live-fan-out/subscribe capability for an
in-progress turn (`sessionCapabilities` only advertises `list`/`delete`/
`close`, no `subscribe`; `session/load` is a history-replay mechanism per
this repo's own earlier live-probing of GooseAcpSession.qml, not a
live-attach mechanism). Making desktop+mobile share one true live session
would mean either rearchitecting GooseAcpSession.qml to talk to `goose
serve` instead of spawning its own process (explicitly off-limits --
Phase 5's own instruction is to leave that file's protocol handling
untouched) or building and migrating to a wholly new unified backend
tonight, which risks the desktop chat overlay's already-proven-live
behavior for an unproven rewrite under time pressure. See BLOCKERS.md.

v3: binds to 127.0.0.1, not the Tailscale interface IP directly. Binding
to the Tailscale IP was the right call for direct phone access (no
firewall changes, not exposed on the raw LAN) before `tailscale serve`
was wired up -- but once `tailscale serve` itself became the tailnet-
facing surface (for real HTTPS), it proxies to `http://localhost:8765`,
and a backend that only listens on the Tailscale IP refuses that
connection (confirmed live: a real 502 from `tailscale serve` the first
time this was tested end to end). `tailscale serve` is now the only
thing exposing this on the tailnet -- binding to loopback only is
strictly more locked-down than before, not less.
"""
import asyncio
import time

from websockets.exceptions import ConnectionClosed
import websockets


HOST, PORT = "127.0.0.1", 8765


class SharedSession:
    """Owns the one `goose acp` process and the set of subscribed clients."""

    def __init__(self):
        self.proc = None
        self.clients = set()
        self._lock = asyncio.Lock()
        self._relay_task = None

    async def ensure_started(self):
        async with self._lock:
            if self.proc is not None and self.proc.returncode is None:
                return
            print("[goose_bridge] starting shared goose acp process", flush=True)
            self.proc = await asyncio.create_subprocess_exec(
                "goose", "acp",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
            )
            if self._relay_task is not None:
                self._relay_task.cancel()
            self._relay_task = asyncio.create_task(self._relay_stdout())

    async def _relay_stdout(self):
        # Broadcasts every line to every currently-subscribed client --
        # this IS the fan-out. A client that's slow/gone by send time just
        # gets a ConnectionClosed, caught and ignored per-client so one
        # dead subscriber can't stall the broadcast to the others.
        while True:
            line = await self.proc.stdout.readline()
            if not line:
                break
            dead = []
            for ws in list(self.clients):
                try:
                    await ws.send(line.decode())
                except ConnectionClosed:
                    dead.append(ws)
            for ws in dead:
                self.clients.discard(ws)
        print("[goose_bridge] shared goose acp process exited unexpectedly "
              f"(code {self.proc.returncode}) -- will restart on next message", flush=True)

    async def send(self, message: str):
        await self.ensure_started()
        self.proc.stdin.write((message + "\n").encode())
        await self.proc.stdin.drain()

    async def stop(self):
        if self.proc is not None and self.proc.returncode is None:
            self.proc.terminate()
            try:
                await asyncio.wait_for(self.proc.wait(), timeout=3)
            except asyncio.TimeoutError:
                self.proc.kill()


session = SharedSession()


async def handler(websocket):
    await session.ensure_started()
    session.clients.add(websocket)
    print(f"[goose_bridge] client subscribed ({len(session.clients)} total)", flush=True)
    try:
        async for msg in websocket:
            await session.send(msg)
    except ConnectionClosed:
        pass
    finally:
        session.clients.discard(websocket)
        print(f"[goose_bridge] client unsubscribed ({len(session.clients)} total)", flush=True)


async def watchdog():
    # Laptop suspend/resume doesn't kill a paused process (Linux suspends
    # the whole machine, not individual processes), so this mainly covers
    # a genuine crash -- restart lazily on the next real message rather
    # than eagerly here, so an idle bridge with zero clients doesn't churn
    # a process no one's using. Just logs staleness for visibility.
    while True:
        await asyncio.sleep(30)
        if session.proc is not None and session.proc.returncode is not None:
            print(f"[goose_bridge] watchdog: shared process is dead (code {session.proc.returncode}), "
                  "will restart on next client message", flush=True)


async def main():
    asyncio.create_task(watchdog())
    async with websockets.serve(handler, HOST, PORT):
        print(f"[goose_bridge] listening on ws://{HOST}:{PORT}", flush=True)
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
