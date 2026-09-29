---
name: game-log-discovery
description: How to find real installed games, their metadata, and their logs on this machine (Steam/Proton, Prism Launcher, journalctl), for the gaming use case. Load when a task needs to discover, identify, or read logs for a locally installed game.
---

# Game and game-log discovery on this machine

Grounded in `desktop/shell/modules/launcher/games/GamesLibrary.qml`'s already-live,
working discovery logic (the Launcher's Games tab) — reuse these exact
paths and patterns rather than guessing new ones.

## Steam
- Library root: `~/.local/share/Steam/steamapps`
- Installed-game metadata: one `grep -H -E '"appid"|"name"|"LastPlayed"'`
  across `steamapps/appmanifest_*.acf` (Valve's own per-app manifest
  format) in a single call, rather than spawning a process per game —
  parse the interleaved per-file matches back into records by filename.
- Cover art: `~/.local/share/Steam/appcache/librarycache`, found via
  `find <dir> -mindepth 2 -iname library_600x900.jpg` — the hash
  subdirectory under `librarycache` isn't derivable from the app id
  alone, hence the `find` rather than a constructed path.
- Proton/game logs and prefixes live under each app's
  `steamapps/compatdata/<appid>/pfx/` (standard Proton layout) — not
  currently read by any code in this repo, but this is the real path
  convention if a task needs a specific game's Proton prefix or its
  `steam-<appid>.log`.

## Prism Launcher (Minecraft)
- Instances root: `~/.local/share/PrismLauncher/instances`
- Per-instance metadata: `instance.cfg` is **INI, not JSON** — one
  `grep -H -E '^(name|lastLaunchTime|totalTimePlayed)='` across
  `instances/*/instance.cfg` in a single call, same one-call-not-N
  pattern as Steam above.
- Cover art: each instance's own `profileImage/` **directory** (not a
  single well-known filename) — found via `find <dir> -mindepth 3
  -maxdepth 3 -path "*/profileImage/*" -type f`, since "does this
  instance have a profileImage" isn't a simple presence check on one
  path.
- Per-instance game logs live under `instances/<name>/minecraft/logs/`
  (vanilla Minecraft logging convention) — not currently read by any
  code here, but this is the real path if a task needs one.

## System-level: journalctl
For anything not covered by an app's own log files (crashes, GPU
driver messages during a play session, gamescope's own output),
`journalctl` is the fallback — cross-reference timestamps against a
game's own launch time (Steam's `LastPlayed` / Prism's
`lastLaunchTime`, both above) to scope the query to the actual play
session rather than scrolling the whole system log.

## The gaming state machine (why this matters beyond just "find the game")
SUPER+G (`ai-workstation-gaming-start`) writes
`/run/ai-workstation/state.json` with `state: "gaming"`, `model: null` —
this is the signal every other AI feature in this repo checks before
deciding whether to load a model onto the (possibly shared) GPU. See the
egpu-dock-undock skill for the full state machine; the short version for
anything gaming-log-related is: check this state file first, and never
have a game-log-reading feature also trigger local model inference on the
same GPU a game might be using.
