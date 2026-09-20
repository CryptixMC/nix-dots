"""Wire-protocol version of the `qubi/*` method namespace.

Clients (the Quickshell QML frontend, the mobile PWA) and the engine are
versioned and deployed separately -- the engine is pinned by a flake lock,
the QML by a git checkout -- so `qubi/status` reports this and a client can
tell it is talking to an engine it does not understand.

Bump `major` for a change an existing client would misread (a removed or
renamed method/field, changed semantics); bump `minor` for purely additive
changes, which clients must tolerate by ignoring unknown keys.
"""

VERSION = "0.1.0"
PROTOCOL = {"major": 1, "minor": 0}
