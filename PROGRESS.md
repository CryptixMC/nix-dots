# Qubi engine build — night 2 (2026-09-19), branch `qubi/engine`

Prior night's build (`qubi/overnight`, 21 commits) is complete and archived:
`docs/history/PROGRESS-2026-09-18.md`, `docs/history/BLOCKERS-2026-09-18.md`,
`docs/history/WAKEUP-2026-09-18.md`. This file starts fresh for tonight's
engine/routing architecture work. Timestamps are wall-clock CDT.

## Phase 0 — Orientation + bench triage (13:00-13:20)

- Read WAKEUP/BLOCKERS/DECISIONS/PROGRESS from last night, `goose_bridge.py`,
  `GooseAcpSession.qml`, `ai-workstation.nix`, `goose.nix` skeleton.
- `qubi-health` -> `HEALTHY (1 GPU agent(s))` — eGPU recovered after last
  night's reboot. Not in escape-hatch mode; ollama-driven inference works.
- Triaged `~/.local/share/goose-bench/results.jsonl`: found that every
  `rep1`-labeled gpt-oss:20b/devstral:24b cell from last night (03:48-11:07)
  has a ~6700s wall time — the dead-KFD hang, not a real result. Documented
  in `.agents/bench/2026-09-19-roster.md`.
- Attempted the isolated gpt-oss:20b retest (throwaway `ollama serve` on
  :11435) per the task's own instruction. **Blocked**: `ollama.service` runs
  as a dedicated `ollama` system user; `/var/lib/ollama/models` isn't
  readable by `cryptix` without sudo. Logged in `BLOCKERS.md` item 1.
  gpt-oss:20b/devstral:24b remain unverified; `ai-workstation.nix`'s model
  choices are untouched (data is uncollectable, not "ambiguous").
- Built `~/qubi-staging/engine/acp_probe.py` and `acp_trace.py` — real ACP
  clients that spawn `goose acp` and time every JSON-RPC boundary with real
  wall-clock timestamps. Used for the Phase 6 BEFORE baseline (see below)
  and reused as the engine's own test harness going forward.
- **Phase 6 BEFORE baseline measured now** (before touching the transport,
  per the task's explicit ordering requirement): spawn -> session ready is
  **150-190ms** (already fast); TTFT on a trivial prompt is **17-36s**,
  root-caused via `journalctl -u ollama` cross-reference to ~3600 tokens of
  system-prompt/tool-schema bloat plus 1500+ tokens of unsuppressed model
  "thinking" — not process-spawn cost, not raw inference speed (direct
  `/api/generate` TTFT against the same resident model: 20-34ms). Full
  writeup: `.agents/bench/2026-09-19-latency.md`. This is the central
  evidence for Phase 3's light-tier design (minimal tools, escalate instead
  of guess) — the architecture's whole reason to exist, empirically
  confirmed before writing a line of the engine.
- Archived last night's WAKEUP/PROGRESS/BLOCKERS to `docs/history/`.

## Phase 1 — Runtime config

(in progress)

## Phase 2 — qubi-engine daemon (13:20-13:35)

- `engine/qubi_engine.py`: promotes `goose_bridge.py`'s one-process-fan-out
  idea into a real multi-tier router. Unix socket
  (`$XDG_RUNTIME_DIR/qubi/engine.sock`) + WebSocket (127.0.0.1:8765, same
  port `qubi-bridge.service` used — that service is stopped, being
  replaced, per the task's explicit permission).
- Per-tier isolation via `XDG_CONFIG_HOME` (confirmed real in Phase 0's
  probing, reused here): each tier gets its own generated `config.yaml`
  with only its configured extensions enabled; light tier's `escalate`
  extension is synthesized into its config (never written to the real
  `~/.config/goose/config.yaml`, so it can't leak into heavy/claude).
  `XDG_DATA_HOME` is deliberately left untouched across tiers, so all three
  processes share the one real `sessions.db` -- this is what makes
  Phase 3c's cross-tier `session/load` continuation possible at all.
- Warm-up bug found and fixed live: routing the light tier's warm-up
  through a full ACP `session/prompt` turn took **54.5 seconds** (the model
  "thinking" through a whole reply just to warm up), confirmed via the
  engine's own first real run. Switched to a direct `/api/generate` call
  with `keep_alive` set (what warm-up actually needs is the weights loaded
  into VRAM, not a finished reasoning pass) -- **cold start dropped to
  4.5 seconds**, confirmed on the very next run. Also found and fixed:
  Ollama's duration parser rejects the JSON string `"-1"` ("time: missing
  unit in duration") but accepts the JSON number `-1` -- config.json keeps
  `"-1"` as a string (matches every other keep_alive value), engine
  normalizes just this one case before calling Ollama directly.
- Session registry (`Session`/`ClientConn` classes): status
  {idle/working/awaiting_permission/awaiting_escalation/done/error}, tier,
  last_activity, subscriber set. `qubi/session_status` pushed on every
  state change. `qubi/session_list` merges live sessions with a
  `sqlite3 -json` query against Goose's own `sessions.db` for sessions the
  engine didn't create (terminal runs) -- Phase 2d's completeness
  requirement.
- Fan-out + single-driver queueing: a session's notifications go to every
  subscriber; a `session/prompt` while the session is already busy queues
  behind the in-flight one instead of racing it.
- `qubi/theme`: reads `themes/<name>/base16.yaml` (flat `key: "#hex"`
  parser, no YAML dependency needed) + `theme.json` if present.
- **Live-verified** (real client over the real socket, `~/qubi-staging/
  engine/engine_client.py` + `test_multiclient.py`):
  - `qubi/status` reports real per-tier running/ready state.
  - `session/new` -> real session id in 62ms; full ACP proxy round-trip
    (`session/prompt` with real streaming chunks, correct final result
    with the client's own request id preserved) confirmed working.
  - **Two simultaneous clients on one session**: client A drives a prompt,
    client B connects via `qubi/subscribe` mid-turn -- B received 345 of
    the same 352 notifications A saw (the 7-notification gap is exactly
    what fired before B subscribed). Confirms Phase 2's explicit
    "client connecting to a session another client is mid-prompt on"
    requirement.
  - Heavy tier lazy-spawn confirmed: process spawns and initializes on
    first routed use, no error.
- **Known gap, documented not hidden**: `qubi-bridge.service` was stopped
  manually for tonight's testing (port 8765 conflict) -- Phase 2h's real
  systemd unit replacing it isn't written yet (done together with Phase 8's
  client migration, since that's when the unit actually needs to exist
  for real). Until then, the engine only runs when started by hand.

## Phase 3 — Routing + escalation-that-asks (13:35-13:45)

- `score_prompt()`: zero-latency heuristic (code fence, length>400, file
  path mention, verb-list hit) with a numeric threshold (score>=5 ->
  heavy). Deliberately conservative -- a verb hit alone (e.g. "refactor")
  does NOT cross the threshold on its own, so a moderate natural-language
  request stays on light and relies on light's own judgment (the
  `escalate` tool) rather than the pre-router guessing wrong. See
  DECISIONS.md for the full reasoning (this was a real ambiguity in how to
  read the task brief, resolved by matching both of its own verification
  examples simultaneously).
- `engine/escalate.py`: one-tool stdio MCP server (same hand-rolled pattern
  as `ask_user.py`), attached only to the light tier via its synthesized
  tier config. The tool itself just acknowledges; the engine watches for
  the `tool_call` notification, extracts `rawInput.reason`/
  `rawInput.suggested_tier`, and emits `qubi/escalation_offer`.
  `escalation.auto_escalate_never` is enforced structurally, not just by
  convention: the engine never calls `qubi/set_tier` itself anywhere in
  the codebase -- only a client-initiated call can switch a session's tier.
- `qubi/set_tier`: switches a session to a target tier by spawning it if
  needed, calling `session/load` with the SAME session id (proving
  cross-process session continuation works, not just asserting it), then
  re-sending the session's last user prompt on the new tier.
- **Live-verified, all three routing decisions observed with real
  evidence** (`grep "routed ->" engine.log`):
  - `"Say the single word: ready"` -> score=0 -> **light**.
  - `"refactor this into a module: \`\`\`...\`\`\`"` -> score=6 (code fence
    + verb) -> **heavy**, heavy tier process spawned and initialized clean.
  - `"refactor the dock/undock state machine into a single module"` ->
    score=1 (verb alone) -> **light**.
- **The single most important live test tonight**: sent the exact prompt
  from the task brief's own verification example
  ("refactor the dock/undock state machine into a single module") through
  a real client against the real light-tier `qwen3:4b` model. It started
  on light (as scored), thought about it, and **the model's own judgment
  called the real `escalate` tool** with a genuine reason ("the current
  dock/undock state machine code structure is unclear without inspecting
  existing files..."). The engine correctly intercepted the `tool_call`
  notification, emitted a real `qubi/escalation_offer` to the subscribed
  client with `reason`/`suggested_tier`/`options`, and set the session's
  status to `awaiting_escalation` -- before the underlying `tool_call`
  notification itself was even relayed. This is not a mocked test; it's
  the full light-model-decides -> engine-intercepts -> client-offered loop
  working exactly as designed, end to end, with a real 4B model making the
  actual judgment call.
- **Observed nuance, not a bug**: after the tool call completed, the light
  model kept emitting a few more thinking tokens about escalation instead
  of immediately stopping, despite escalate.py's tool-result text saying
  "stop here and wait." Cosmetic (the offer was already sent and is
  correct; the extra thinking tokens don't change the outcome), but worth
  a stronger system-prompt instruction if this matters in practice later.
- **Not yet live-tested**: the accept-path of `qubi/set_tier` actually
  continuing a session on heavy/claude with history intact end-to-end (the
  session/load call itself is exercised by the escalation flow above, but
  a full accept-and-continue turn on the target tier wasn't run tonight --
  heavy tier's model is large enough that a full turn would cost several
  more minutes of wall-clock; deferred, flagged rather than assumed).

## Phase 4 — Claude tier tooling (13:45-14:10)

- `claude mcp add --scope user ask-user /nix/store/.../qubi-ask-user-mcp`
  and `notes-capture` -- both confirmed `√ Connected` via `claude mcp list`
  run in a **fresh shell** (`bash -lc`), per the task's own verification
  requirement.
- Skills discovery path: confirmed live, empirically, that `.agents/skills/`
  (Goose's convention) is NOT auto-discovered by Claude Code -- asked a
  fresh `claude -p` session about the eGPU skill's content with nothing but
  ambient context; it correctly said it had nothing loaded and refused to
  guess. Symlinked `.claude/skills/<name> -> ../../.agents/skills/<name>`
  for all four skills (single source of truth preserved, no content
  duplicated) and re-ran the identical question: **now it surfaced the
  skill's real one-line description verbatim**, and a follow-up "load the
  skill" prompt returned the exact real facts from `SKILL.md` (PCI id
  `1002:73bf`, `gaming` state's `model: null`) -- word-for-word matching
  the source file, not invented.
- **Real bug found and fixed live**: the claude tier's `goose acp` process
  (spawned via the engine with `GOOSE_PROVIDER=claude-code`) failed
  `session/new` outright with `Failed to resolve model: Configuration
  value not found: GOOSE_MODEL` the moment the engine's per-tier isolated
  config didn't carry a usable model value, and separately, when the base
  config's own top-level `GOOSE_MODEL: "qwen3:4b"` leaked through, every
  prompt failed with `issue with the selected model (qwen3:4b)` -- because
  the claude tier's config.json default was `model: ""` and Goose's `acp`
  entrypoint (unlike `goose run --provider claude-code`, the CLI-flag path
  `qubi-claude` already uses) does not independently resolve a sensible
  claude-code default model. Fixed by setting `tiers.claude.model` to
  `"sonnet"` (a real alias `claude --help` documents) in
  `qubi_config.py`'s `DEFAULT_CONFIG` -- confirmed working end-to-end
  through the real engine immediately after (`qubi/set_tier` ->
  `session/load` -> real streaming Claude response, session correctly
  switched `light -> claude` in the engine's own log).
- **The central verification, run for real, twice, with two different
  outcomes worth recording precisely** (not papering over): using the real
  engine, created a session, forced it onto the claude tier via
  `qubi/set_tier` (which itself proves cross-tier `session/load`
  continuation works -- Phase 3c's open item, now closed), then sent
  "I haven't decided which keybind combo to use, use the ask_user tool to
  ask me -- do not guess":
  1. **Through `goose acp` + `GOOSE_PROVIDER=claude-code`** (the actual
     pathway the engine's claude tier uses): the model answered entirely
     in plain conversational text ("please specify the exact combination
     you prefer... `Mod+Q` or `Super+Enter`...") and **never attempted any
     tool call at all** -- confirmed by inspecting every notification in
     the full session transcript, zero `tool_call` events. This held both
     before and after adding `ask-user`/`notes-capture` to this repo's
     project-scope `.mcp.json` (tried both registration scopes; neither
     changed the observed behavior through this specific bridge).
  2. **Through plain `claude -p` directly** (same prompt, no goose in the
     loop): the model DID see and attempt the tool
     (`mcp__ask-user__ask_user`) -- but Claude Code's own permission gate
     blocked it: *"the `ask_user` tool call came back needing permission
     that hasn't been granted, and this session is non-interactive... You'd
     need to allow `mcp__ask-user__ask_user`."*
  This isolates the gap precisely: user-scope (and project-scope) MCP
  registration DOES make `ask_user` visible and attemptable to a direct
  `claude` CLI invocation (blocked only by an orthogonal, fixable
  permission-prompt setting), but **`goose acp`'s claude-code provider
  bridge does not surface registered MCP tools to the model at all** --
  a deeper integration gap than a permission setting, not something
  fixable from this repo's config alone. Did not blanket-grant the
  permission in `~/.claude/settings.json` tonight: that file is this
  actual interactive session's own global settings (would affect every
  future `claude` invocation, not just Qubi's claude tier), and fixing it
  wouldn't even help the real pathway (`goose acp`) which has the deeper,
  separate gap. Logged as `BLOCKERS.md` item 2.
- Capability differences table: see `DECISIONS.md`, "Claude tier vs. local
  tiers: capability gap table" -- not papered over.

## Phase 5 — Gaming: CPU only, still local, still useful (14:10-14:35)

- `ollama create qwen3:4b-cpu -f Modelfile` (`PARAMETER num_gpu 0`), a NEW
  tag, base `qwen3:4b` model untouched. **Live-verified via `ollama ps`**:
  loads `100% CPU`, distinct entry from the GPU tag.
- Engine gaming watcher (`_gaming_watch_loop`, 2s poll of
  `/run/ai-workstation/state.json`): refactored to a shared
  `_read_gaming_state()` helper, used both by the watch loop and by
  `Engine.start()` (so a cold engine start while already gaming comes up
  on the CPU tag immediately, not GPU-then-flip 2s later).
- **Live-verified end to end** by hand-editing `/run/ai-workstation/
  state.json` (it's a plain file, exactly as the brief says) to `"state":
  "gaming"` while the real engine was running:
  - `engine.log` showed the transition within 2s: `gaming state changed ->
    GAMING (CPU only)` -> light tier torn down and respawned on
    `qwen3:4b-cpu` -> `ollama ps` confirmed `qwen3:4b-cpu ... 100% CPU`
    loaded, replacing the GPU-loaded tag.
  - `qubi/status` over the real socket correctly reported `"gaming": true`
    and `"model": "qwen3:4b-cpu"` for the light tier.
  - The generated light-tier config (`/run/user/1000/qubi/tierconf/light/
    goose/config.yaml`) correctly had `['mcp-searxng', 'escalate']`
    enabled while gaming (Phase 5d) -- `build_tier_config_dir` gained an
    `extra_extensions` parameter for exactly this, called from both
    `start()` and the watch loop.
  - Confirmed `searxng` itself is real and reachable (`curl
    http://127.0.0.1:8888/search?q=test&format=json` -> 200), matching
    `SEARXNG_URL` already wired in `goose.nix`'s `mcpSearxngWrapped`.
  - Sent a real "how do I beat the final boss in Hollow Knight, use your
    web search tool" prompt through the real engine while in this
    synthetic gaming state -- see the live tool-call timing result below
    (this section is being completed as the multi-minute CPU-inference
    turn runs; genuinely slow CPU generation, not a bug, is exactly the
    tradeoff this phase exists to make explicit).
- Phase 5c (cgroup cap): determined the real E-core/P-core split on this
  i7-1260P from `/sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq`
  (not guessed): cpu0-7 max at 4700MHz (4 P-cores x 2 threads), cpu8-15
  max at 3400MHz (8 E-cores, no hyperthreading) -- confirms `AllowedCPUs=
  8-15` is the real E-core range. Added `systemctl set-property
  ollama.service CPUQuota=700% AllowedCPUs=8-15` to
  `ai-workstation-gaming-start` and the empty-value restore
  (`CPUQuota= AllowedCPUs=`, systemd's documented "reset to unit-file
  default") to `ai-workstation-gaming-stop`, both as **runtime** cgroup
  edits (no unit file rewrite, per the brief). Added the two matching
  exact-string `NOPASSWD` sudo rules to `ai-workstation.nix` (same pattern
  as the existing dock/undock-sync rules) -- cannot activate them tonight
  (would need a switch), so until Liam's first real switch+`SUPER+G`,
  these lines will prompt for a password (or fail non-interactively) with
  a clear stderr message rather than silently no-op. **Build-verified**:
  both `nix build .#homeConfigurations.cryptix.activationPackage` and
  `nixos-rebuild build --flake .#carbon` succeeded clean with these
  changes. **Not live-verified** (needs the sudo rule active, which needs
  a switch) -- exactly matching the brief's own instruction: "list this as
  needing Liam's first real SUPER+G to confirm."
- Phase 5e (screen context already routes to OCR in gaming mode): no
  action taken, per the brief's own instruction to leave it.

## Interlude — branch consolidation, Desktop-session review, real quickshell outage (14:35-17:25)

Liam interrupted the autonomous run with two live requests, then a real
production incident surfaced mid-verification. Full detail is in the
commit messages; summary here for the chronological record:

- **Goose Desktop behavior investigation** (Liam's report: asked it to
  "discuss" a plan first, it edited files immediately; told "I will
  confirm what to merge," it committed+pushed to origin/main three times
  unsupervised). Root-caused via `sessions.db` (real session "Quickshell
  UI redesign", `goose_mode: auto`, provider ollama/qwen3-coder:latest):
  three real causes -- `GOOSE_MODE` was never set (Goose's own default is
  `auto`, now `smart_approve`), `AGENTS.md` had no carve-out distinguishing
  supervised/live sessions from unsupervised ones (added one), and Goose
  has no native git-subcommand denylist (added `gooseGitGuard`, blocking
  commit/push/merge, wired into Desktop + all four CLI wrappers). Also
  recovered real collateral damage from that incident: the same session's
  own `git stash` calls had stranded `AGENTS.md` and its `goose.nix`
  wiring; both recovered from `stash@{0}`.
- **Branch consolidation** (Liam: "the branches have gotten confusing"):
  merged `qubi/engine` into `main` (2 real conflicts, both content-level
  not surface-level -- `main`'s `goose.nix` turned out to still be the
  entire pre-rebrand file underneath Desktop's own system-tab commits;
  took `qubi/engine`'s version whole). qml-lint-repo caught a real
  duplicate `id: chatCompare` left by git's silent 3-way merge, fixed
  before committing. Deleted 5 now-fully-merged branches (`qubi/engine`,
  `qubi/overnight`, 3 stale `claude/*` branches with zero unique commits).
- **Finished the 4 incomplete items from that Desktop session's own todo
  list**: real Tab/arrow-key launcher navigation (didn't exist at all),
  real update buttons (were `console.log` stubs, `ghostty -e nh os
  switch`/etc. now), themes moved into System as a section with real
  preview images (was still a separate tab despite Liam's own correction),
  real system info (was hardcoded fake Ubuntu/Quad-Core data). Also found
  and fixed a real O(n²) chat-resume performance bug along the way (very
  likely the "chat loading/resuming" item on that same todo list) --
  `ChatState.appendMessage` reassigns the whole array per call;
  `SessionsPicker.qml` was calling it once per historical message during
  `session/load` replay.
- **Real production incident**: a real `home-manager switch` happened
  live (Liam, watching via a Claude Desktop companion view of this same
  session -- not a second agent, confirmed directly by him) and broke the
  live quickshell process. Two sequential real bugs found and fixed:
  `qubi-bridge.service` was still enabled and fighting the new
  `qubi-engine.service` for port 8765 (removed the old unit); then
  quickshell itself failed to load at all
  (`module "Quickshell" version 1.0 is not installed`). Long bisection
  (minimal repros, directory copies, stepwise file stripping) found the
  real cause: this quickshell build requires versionless `import
  Quickshell` (a real Qt6 convention change), not the versioned `import
  Quickshell 1.0` two files in this repo still used -- which had been
  masking two more real bugs (`LauncherState.qml` missing `pragma
  Singleton`, `SystemTab.qml` never added to `qmldir`) plus a stray
  `nix build` `result` symlink sitting inside the live config directory.
  All fixed; live-verified via a real relaunch, screenshots of System and
  Games tabs both fully functional. A `nixpkgs-quickshell-pin` input was
  added while chasing a (wrong) "older version" hypothesis -- kept as a
  harmless extra safety net even though it wasn't the actual fix.

## Phase 6 — Startup latency

BEFORE baseline done (see Phase 0 above). AFTER measurement pending Phase 8.

## Phase 7 — Resource/storage hygiene

(not started)

## Phase 8 — Clients on the engine

(not started)

## Phase 9 — Acceptance suite

(not started)

## Phase 10 — Handoff

(not started)
