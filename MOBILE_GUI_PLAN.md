# Mobile GUI for Qubi sessions

## Architecture

```
Phone browser (mobile_gui.html) --WebSocket--> qubi-bridge --stdio JSON-RPC--> goose acp
```

`qubi-bridge` (`goose_bridge.py`, wrapped in `modules/home-manager/apps/goose.nix`)
is a dumb, symmetric line relay: it spawns a `goose acp` subprocess per WebSocket
client and forwards each stdout line to the client verbatim, and each client
text frame to stdin as a line. It does not parse, interpret, or special-case
the ACP protocol in any way — `mobile_gui.html` speaks the real ACP JSON-RPC
protocol directly, the same protocol `quickshell/modules/chat/GooseAcpSession.qml`
already speaks to drive the desktop chat overlay.

This was chosen over `goose serve`'s own HTTP/WebSocket server after live
investigation found its REST endpoints mostly 404 unless authenticated
(`--dangerously-unauthenticated` implies auth is required by default) and its
real route surface was never fully mapped. Relaying to `goose acp` directly
sidesteps that uncertainty entirely and reuses a protocol already proven
working in this repo.

The bridge binds specifically to this machine's Tailscale interface address
(`100.66.17.61:8765`), not `0.0.0.0` and not `localhost` — reachable from a
phone over Tailscale with no NixOS firewall changes, and not exposed on the
raw LAN.

## Usage

After `nh home switch`, two systemd user services start automatically and
restart on failure (`systemd.user.services.qubi-bridge` and
`qubi-mobile-static`, both in `modules/home-manager/apps/goose.nix`):
`qubi-bridge` runs the WebSocket relay on `100.66.17.61:8765`, and
`qubi-mobile-static` serves this repo's root directory as plain static
files on `100.66.17.61:8901` (a plain `python3 -m http.server`, bound to
the Tailscale interface only). No manual server-starting is needed after
the switch — check with `systemctl --user status qubi-bridge
qubi-mobile-static` if something seems off.

From a phone on the same tailnet: visit `http://100.66.17.61:8901/mobile_gui.html`.
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
