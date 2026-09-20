# Qubi protocol

One JSON object per line (unix socket) or per websocket frame. Two kinds of
message share the connection:

- **ACP JSON-RPC** (`initialize`, `session/new`, `session/load`,
  `session/prompt`, `session/cancel`, `session/update`,
  `session/request_permission`, ...). Forwarded to the `goose acp` process of
  whichever tier the session is bound to, with request ids remapped so
  concurrent clients cannot collide and session ids rewritten so a client
  keeps seeing the id it subscribed to across tier switches. A client that
  can drive `goose acp` over stdio can drive the engine by swapping the
  transport.
- **`qubi/*`** engine methods, handled by the engine and never forwarded.

Transports: `$XDG_RUNTIME_DIR/qubi/engine.sock` (desktop) and
`ws://127.0.0.1:8765` (mobile; the engine has no authentication, so front it
with something that does, e.g. `tailscale serve`).

## Versioning

`qubi/status` returns `protocol: {major, minor}` (`python/src/qubi/protocol.py`).
The engine is usually pinned by a flake lock and the QML by a git checkout,
so they can drift apart. Clients compare `major` with the one they were
written for (`QubiConfig.protocolMajor`, `PROTOCOL_MAJOR` in the PWA) and
warn on mismatch. `major` changes when an existing client would misread
something; additive changes bump `minor`, and clients must ignore keys they
do not know.

## Requests

| Method | Params | Result |
|---|---|---|
| `qubi/status` | – | `protocol`, `version`, `defaultCwd`, `state` (`docked`\|`undocked`\|`gaming`), `cpuOnly`, `gaming`, `tiers.<name>.{running,ready,starting,model}` |
| `qubi/subscribe` | `session`, `tier?` | `subscribed` |
| `qubi/session_list` | – | `sessions[]`: live engine sessions plus goose's own sessions.db |
| `qubi/session_usage` | `session` | `totalTokens`, `accumulatedTotalTokens` (summed over every tier's goose session) |
| `qubi/set_tier` | `session`, `tier` | `session`, `tier`; re-sends the last user prompt to the new tier |
| `qubi/installed_models` | – | `models[]`: `name`, `sizeBytes`, `modifiedAt`, `parameterSize` |
| `qubi/use_model` | `session`, `model` | Binds this one conversation to an ephemeral `model:<tag>` tier; touches no configuration |
| `qubi/extensions` | – | `enabledCount`, `extensions[]` from goose's config.yaml |
| `qubi/theme` | `name?` | `base16`, `manifest` for clients with no filesystem |

## Notifications (engine → client)

| Method | When |
|---|---|
| `qubi/session_created` | Another client created a session (`session`, `tier`) |
| `qubi/session_status` | `status`, `phase`, `phaseDetail`, `tier`, `lastActivity` for a subscribed session |
| `qubi/escalation_offer` | The light tier called its `escalate` tool: `reason`, `suggested_tier`, `options`. The engine **never** switches tiers on its own; a client answers with `qubi/set_tier` or declines |

## Quickshell IPC targets

The QML frontend's `IpcHandler` targets are a stable interface for keybinds
(`quickshell ipc -p <shell> call <target> <function>`):

`chat` (`toggle`, `send(text)`, `compare`), `sessions`, `modelbrowser`,
`extensions`, `clipboard`, `askuser` (`show(requestId)`, used by the ask-user
MCP server), `screenctx`, `voice`, `notes`, `qubi-model`.
