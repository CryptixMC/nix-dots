# Mobile GUI for Qubi sessions

## Architecture

```
Phone browser (mobile_gui.html) --WebSocket--> qubi-bridge --stdio JSON-RPC--> goose acp
```

`qubi-bridge` (`goose_bridge.py`, wrapped in `modules/home-manager/apps/goose.nix`)
is a dumb, symmetric line relay: it holds exactly ONE `goose acp` subprocess for
the bridge's entire lifetime and fans its stdout out to every currently-connected
WebSocket client (broadcast), and relays any connected client's input to that
same shared subprocess's stdin. It does not parse, interpret, or special-case
the ACP protocol in any way — `mobile_gui.html` speaks the real ACP JSON-RPC
protocol directly, the same protocol `quickshell/modules/chat/GooseAcpSession.qml`
already speaks to drive the desktop chat overlay.

**v2 (2026-09-18): fixed the "second phone can't see a session already in
progress" gap.** v1 spawned a *new* `goose acp` process per WebSocket
connection — correct for exactly one client, but meant N phones (or a phone
relative to the desktop) each got a fully independent process and session
from a cold start, never seeing each other's live activity. Now every
subscriber sees the same broadcast stream from the one shared process —
live-verified with two simultaneous WebSocket clients receiving byte-identical
responses to a request sent by only one of them. This does NOT unify with the
desktop chat overlay's own separate `goose acp` process (`GooseAcpSession.qml`)
— see BLOCKERS.md/DECISIONS.md for why (investigated `goose serve`'s native
HTTP/WebSocket surface as a possible shared backend for both; confirmed it's
real — POST to enqueue + GET with `Accept: text/event-stream` and an
`Acp-Connection-Id` header to receive results, verified live — but found no
evidence of a live cross-connection subscribe/fan-out capability, and
rearchitecting `GooseAcpSession.qml` to depend on it was judged too risky to
attempt against an already-proven-live desktop feature under time pressure).

This custom relay was chosen over `goose serve`'s own HTTP/WebSocket server
after live investigation (originally inconclusive, re-investigated more
deeply 2026-09-18: confirmed real POST+SSE semantics, a working `/health`
endpoint, and that it requires a tailnet-scoped browser-auth-free
`--dangerously-unauthenticated` flag to use at all) found no native
multi-subscriber session sharing — the actual problem this rework needed to
solve. Relaying to `goose acp` directly and doing the fan-out ourselves
sidesteps that gap entirely and reuses a protocol already proven working in
this repo.

**v3 (2026-09-18, later same night): binds to loopback, fronted by `tailscale
serve`.** Originally bound directly to this machine's Tailscale interface
address (`100.66.17.61`) — the right call before Serve was wired up (reachable
over Tailscale, not exposed on the raw LAN, no firewall changes). Once
`tailscale serve` became the tailnet-facing HTTPS surface, its local proxy
connects to `http://localhost:PORT` — a backend bound only to the Tailscale IP
refuses that connection (a real, live-confirmed 502). Both services now bind
to `127.0.0.1` only; `tailscale serve` is the sole thing exposing them on the
tailnet, which is strictly more locked-down than the old direct-bind setup,
not less.

## Usage

After `nh home switch`, two systemd user services start automatically and
restart on failure (`systemd.user.services.qubi-bridge` and
`qubi-mobile-static`, both in `modules/home-manager/apps/goose.nix`):
`qubi-bridge` runs the WebSocket relay on `127.0.0.1:8765`, and
`qubi-mobile-static` serves this repo's root directory as plain static
files on `127.0.0.1:8901`. A third service, `qubi-tailscale-serve`, puts
both behind `tailscale serve` for real HTTPS (see BLOCKERS.md for the
one-time `tailscale serve` tailnet approval + `sudo tailscale set
--operator=$USER` this needs before it can actually submit its config).
No manual server-starting is needed after the switch — check with
`systemctl --user status qubi-bridge qubi-mobile-static
qubi-tailscale-serve` if something seems off.

From a phone on the same tailnet: visit `https://<this-machine's-tailnet-hostname>/mobile_gui.html`
(find the hostname with `tailscale status --self` or `tailscale serve status`).
It's installable — `manifest.json` + `icon-192.png`/`icon-512.png` make it
add-to-home-screen capable on both Android (Chrome) and iOS (Safari), and
it opens standalone (no browser chrome) once added.

## What's implemented

- Session picker, populated live via the real ACP `session/list` method —
  shows actual existing Qubi session history (confirmed live: 50 real
  sessions), not a fake or hardcoded list.
- Clicking a session calls `session/load` and replays its real prior
  conversation history into the message view.
- A text input + send button that calls `session/prompt` and streams the
  live response back via `session/update` notifications, rendered
  incrementally into a single growing message bubble per turn (not
  fragmented per network chunk).
- Graceful recovery if a session fails to load (e.g. a recipe-based session,
  which can't be resumed via `session/load` — the same known limitation
  already handled in the desktop `SessionsPicker.qml`) — returns to the
  session list with a status message instead of getting stuck.
- Dark, mobile-sized, no-build-step, no-CDN-dependency styling.

## Verified live, end to end

Using a real running `qubi-bridge` and a real browser (via the
Claude Code preview tooling, not just code inspection):
- Real `initialize` handshake → real `agentInfo` naming `goose 1.47.0`.
- Real `session/list` → real session data rendered in the picker.
- Real `session/load` on an existing session → real prior conversation
  history (a genuine "what is 9 times 8" / "72" exchange) replayed
  correctly into the message view.
- Real `session/prompt` → a live model response streamed back and rendered
  as a single coherent message ("the quick brown fox jumps").
- Sending a second message after the first succeeds correctly re-enables
  the input (an earlier bug where the UI could get stuck disabled after
  one message was found and fixed during this verification pass).
