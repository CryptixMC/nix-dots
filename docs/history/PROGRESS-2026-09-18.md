# Qubi overnight build — PROGRESS

Branch: `qubi/overnight` (off `main` @ 3e46106). Started 2026-09-18 ~01:50 CDT.

**Read before resuming**: this is a *resumption*, not a fresh start. When this session picked up,
`main`'s working tree already had substantial uncommitted Phase 1 work sitting in the index —
rebrand to Qubi, zram.nix, qubi-health.nix, amdgpu runpm/aspm params (already present, older),
hyprland keybinds reserved (U/I/O/N/SHIFT+D), theme tokens reserved, model pulls done (gpt-oss:20b,
devstral:24b, qwen3-vl:4b, nomic-embed-text — pulled ~21-25min before this session started), mobile
bridge packaged as a systemd user service. No commits were lost (checked `git reflog` — clean).
This was very likely an earlier pass of this exact overnight task in the same wall-clock night,
interrupted (context compaction or session boundary) before it committed anything or wrote these
log files. Read `TODO.md` §7 in full before assuming anything is unbuilt — it's an extremely
detailed, dated log of everything done on this project through 2026-09-17, including hard-won
findings (tool-calling reliability per model, context-length bugs, power-profile CPU throttling,
dock/undock sync bugs) that would be wasteful to rediscover.

## Phase 0 — Orientation — DONE 01:55
- Read TODO.md (full, 350 lines), AGENTS.md, MOBILE_GUI_PLAN.md, README.md (no Qubi/goose content —
  pure desktop-shell doc, not touched by this task).
- `df -h /`: 69GB free of 672GB (90% used). Above the 60GB floor — not a blocker, but model pulls
  eat into it fast; watch before pulling anything else large.
- Confirmed live Quickshell (PID 4588) running, no crash-relevant journal entries.
- **Found and fixed a real gotcha**: my Bash tool's inherited `LD_LIBRARY_PATH` includes a stray
  `gcc-15.3.0-lib` that breaks `hyprctl` (GLIBCXX version mismatch) when called directly from this
  shell. Workaround confirmed live: `env -i HOME=$HOME XDG_RUNTIME_DIR=/run/user/1000
  HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl ...` — clean env sidesteps it. Use this pattern for any
  hyprctl call from a Bash tool call for the rest of this session.

## Phase 1 — Rebrand + system modules
- [x] 1a rebrand — already done pre-session: user-facing strings say "qubi" (chat overlay "message
      qubi…", session-load error mentions qubi-code), script names renamed with `qubiAliases`
      backward-compat shims for old names, engine internals (GOOSE_* env vars, `goose acp`, `goose`
      binary, nixpkgs attrs) correctly left alone. Verified via grep — no stray `goose-*` script refs
      outside legitimate engine/env-var/debug-log context.
- [x] 1b zram — `modules/nixos/services/zram.nix` exists (50%, zstd), imported in
      `hosts/carbon/configuration.nix`.
- [x] 1c amdgpu runpm/aspm — already present in `amd.nix` from a prior session (`amdgpu.runpm=0`,
      `amdgpu.aspm=0`, `pcie_aspm=off`, kernel pinned `linuxPackages_6_18`). Did NOT re-derive
      whether 6.18.50 carries the 2026 kfd-surprise-disconnect/runtime-PM patches — no changelog
      access to confirm kernel-patch provenance offline; the existing runpm=0 workaround makes it
      moot either way (compute never attempts runtime PM regardless of whether the kernel fix
      landed). Documented as-is rather than guessing.
- [x] 1d qubi-health.nix — exists, 5-min timer, advisory-only (rocminfo vs lspci mismatch →
      hyprctl notify, never kills/restarts). **Gap found**: master task asked for a `qubi-health` CLI
      printing HEALTHY/DEAD-KFD-REBOOT-REQUIRED/WEDGED-RUNNER/EGPU-ABSENT — the existing module only
      has the systemd timer script, no standalone CLI and no D-state-wedged-runner detection. Added
      both (see commit).
- [x] 1e sleep hook — `ai-workstation-suspend-evict` in `ai-workstation.nix` (evicts loaded Ollama
      models before suspend, `|| true` throughout, bound to `sleep.target`). Already done.
- [x] 1f model pulls — gpt-oss:20b, devstral:24b, qwen3-vl:4b, nomic-embed-text all present in
      `ollama list` (pulled ~21-25min pre-session). Devstral tag: `devstral:24b` — this **is** the
      correct/only Devstral Small tag on the Ollama library (no separate "Small" suffix tag exists).
- [x] 1g keybinds reserved — U/I/O/N/SHIFT+D added to hyprland.nix with graceful-fail IPC calls
      (target doesn't exist yet → "Target not found", exit 0, confirmed by prior session's comment).
      NOTE: master task said SUPER+X for clipboard, but SUPER+X was already taken by the extensions
      manager (`445dc88`) — prior session correctly substituted SUPER+U instead and documented why.
      Keeping this deviation (logged in DECISIONS.md).
- [x] 1h theme tokens + host imports — ThemeDefaults.qml has placeholder token families
      (clipboard/screenctx/voice/notes/compare), hosts/carbon/*.nix import zram+qubi-health.
      `qubi-mcp.nix` import commented out in home.nix (module doesn't exist yet — Phase 4 will
      create it and uncomment).
- [x] 1i `nix flake check` + `nixos-rebuild build --flake .#carbon` — both clean, re-confirmed
      again at the very end of the night (Phase 9) after every subsequent phase's changes too.

*** SWITCH GATE — see SWITCH-1.md once written ***

## Phase 2 — Model roster benchmark — BLOCKED partway through (see BLOCKERS.md item 1)
Extended `goose-bench.nix` with 2 new task shapes (author-new-file, error-recovery-chain) on top
of the existing 3, committed (813099f). Launched the full matrix in the background at 01:56:
5 models (gpt-oss:20b, devstral:24b, qwen3-coder:latest, qwen3.6:latest, qwen3:4b) x 5 shapes x 3
repeats = 75 cells, `think=false` throughout (established best default per TODO.md), all docked.

**The very first cell (gpt-oss:20b, append-naive) triggered — or at least coincided with — the
eGPU hitting the dead-KFD state** (see BLOCKERS.md item 1): `qubi-health` reported
`DEAD-KFD-REBOOT-REQUIRED`, `rocminfo` showed 0 GPU agents despite `lspci` showing the card
present, and a fresh Ollama request hard-timed-out. This is the exact same failure signature
TODO.md §7 already documents from three earlier incidents this project — genuinely plausible this
is a real, reproducible gpt-oss:20b/harmony-format issue on this hardware, not a fluke, though I
could not get a clean pass/fail verdict before the crash to confirm that specifically. **Treat
gpt-oss:20b as provisionally suspect** until it's re-tested in isolation post-reboot (its own
throwaway `ollama serve` instance, not the live service, per TODO.md's own established pattern
for risky model tests).

Killed the stuck benchmark process cleanly (confirmed no orphans via the bridge/process checks
done in later phases). Did **not** get to: re-deriving safe context lengths with zram now
enabled, the qwen2.5-coder Modelfile chat-template fix test, or updating `ai-workstation.nix`'s
model choices (nothing to update — the benchmark that would justify a change never completed).
**This phase needs a resume, not a redo** — `~/.local/share/goose-bench/results.jsonl` already
has prior-night baseline data, and the harness is resumable by label once you're back on a
healthy GPU. This is the one phase that is genuinely incomplete, not just risk-mitigated.

## Phase 3 — Clipboard transform (SUPER+U) — DONE
Built `quickshell/modules/clipboard/{ClipboardState.qml, ClipboardTransform.qml, qmldir}` per the
staging protocol: authored in `~/qubi-staging/quickshell/` (mirrors real repo structure, theme/
symlinked in), launched a second Quickshell instance against a staging-only shell.qml that
imports *only* this module, confirmed clean load + repeated IPC toggle with no crash, *then*
copied into the repo and uncommented the shell.qml registration. Confirmed the live shell picked
it up via hot-reload (log: "Reloading configuration... Configuration Loaded", no new warnings)
and did a real end-to-end round trip against the live instance (real wl-copy, real IPC call).
Direct Ollama `/api/generate` (not goose acp) — matches `ModelBrowser.qml`'s `/api/pull` pattern.
Decisions logged in DECISIONS.md: gaming fully disables the feature (no fallback model, never
contend with the game's GPU), model comes from `ai-workstation.nix`'s live routing (falls back to
qwen3:4b), 8000-char cap.

**Gotcha for future-me**: `find /nix/store -maxdepth 1 -iname "*qml-lint-repo*"` can return a
*stale* build from before a source edit (Nix never GCs automatically) — I burned real time
chasing a false "exit 255" regression that was actually an old cached binary with
`--unresolved-type error` instead of the current source's `--unresolved-type disable`. Always
`nix build .#homeConfigurations.cryptix.activationPackage --no-link --print-out-paths` fresh and
resolve the tool's path *from that build's closure*, don't grab an ambient store path by glob.
Also: capturing `$?` after a `| tail` pipe captures `tail`'s exit code, not the piped command's —
redirect to a file instead of piping when the exit code matters.

## Phase 4 — MCP servers — DONE
- 4a `ask-user`: `mcp-servers/ask_user.py`, hand-rolled stdio JSON-RPC, verified via a direct
  protocol probe (initialize/tools-list/tools-call) and a full round trip against a live staging
  Quickshell instance (new `quickshell/modules/askuser/` overlay, staging-validated then
  registered). Skips MCP elicitation entirely — couldn't verify live whether the pinned Goose
  supports/propagates it (blocked by the dead-KFD state, see BLOCKERS.md) — blocks synchronously
  inside the tool call instead, which works regardless of client-side elicitation support.
- 4b `notes-capture`: `mcp-servers/notes_capture.py`, same protocol pattern, plus a `--cli` mode
  shared by both the MCP tool path and the new SUPER+N `quickshell/modules/notes/` overlay.
  Targets `.agents/inbox.md` (low-confidence default — real Obsidian vault found at
  `~/Documents/Vault` but has no established capture-folder convention to guess at; see
  DECISIONS.md).
- 4c `research-agent.yaml` recipe chains mcp-searxng + mcp-server-fetch + notes-capture.
  Validated with a real `goose recipe validate` run (not just eyeballed). **All three component
  MCP servers individually tested for real, later in the night**: `mcp-searxng` against the real
  local SearXNG instance (confirmed reachable, `curl 127.0.0.1:8888/search?...` returns real
  results) — a genuine `searxng_web_search` tool call returned real search results for "nixos
  flakes"; `mcp-server-fetch` genuinely fetched `https://nixos.org` and returned real page
  content; `notes-capture` already verified in 4b. Only the LLM-driven orchestration of the full
  chain (search → fetch → synthesize → capture, as one autonomous run) remains untested — that
  needs real inference, blocked by BLOCKERS.md item 1.
- 4d Four `.agents/skills/*/SKILL.md` files (nix-dots-conventions, quickshell-qml-patterns,
  egpu-dock-undock, game-log-discovery), each grounded in facts already gathered this session.
  Confirmed real discovery via `goose skills list` (pure filesystem scan, no inference needed) —
  empirically found Goose additively discovers project-local `.agents/skills/` from CWD alongside
  the global `~/.agents/skills/` ones already on this machine. Flipped `skills` extension to
  `enabled = true` in the main config.

All of Phase 4 is build-verified and protocol-level-verified; the parts that need a real LLM tool
call in the loop (e.g. Goose actually deciding to call `ask_user` or `capture_note` mid-session)
could not be fully live-verified tonight — blocked by the dead-KFD state (BLOCKERS.md item 1).

**Attempted a partial workaround, got a real but nuanced result**: ran a live `goose acp` session
via the `claude-code` provider (bypasses the dead GPU) and asked it to call `ask_user` directly.
It correctly refused — reported it has no such tool, only its own native Claude Code tools
(Bash/Read/Write/Edit/Agent/etc.), no MCP tools at all, not even ones registered in
`config.yaml`. **This is very likely specific to the `claude-code` provider, not evidence against
Phase 4a/4b working under the intended `ollama` provider**: TODO.md §7 already documents (from
before tonight) that `claude-code`/`claude-acp` hand the *entire* tool loop to Claude Code's own
tooling, bypassing Goose's own extension system — plain providers like `ollama` read
`config.yaml`'s `extensions` block directly through Goose's own tool loop, a structurally
different path this test didn't exercise. Flagging this clearly rather than either hiding a
negative result or letting it be misread as disproving Phase 4a/4b — the actual target
configuration (ollama + config.yaml stdio extensions) remains genuinely untested, blocked by
BLOCKERS.md item 1. **First thing worth checking once the GPU is back**: a plain `qubi-chat`
session asking a question that should trigger `ask_user`.

## Phase 5 — Chat overlay completion — DONE
Found most of this already built pre-tonight (markdown via `Text.MarkdownText`, mode toggle pill,
permission UI rendering the request's own `options[]` dynamically — already exactly right, never
hardcoded — primary + subagent model selectors, per-message copy, timestamps, regenerate, stop).
Built what was actually missing:
- Side-by-side compare (SUPER+SHIFT+D): new `GooseAcpPane.qml` (separate, smaller reimplementation
  of the proven ACP protocol subset, GooseAcpSession.qml itself untouched) + `ChatCompare.qml`,
  two independent `goose acp` processes. Structurally validated in staging; could NOT live-verify
  an actual two-model response — blocked by the dead-KFD state.
- Thought bubbles were already rendered but always fully expanded — now default-collapsed with
  click-to-expand, closer to "collapsible thinking panel."
- Scope cut, logged in DECISIONS.md: per-fenced-code-block copy buttons not built (whole-message
  copy already existed and covers the practical need; real per-block copy needs a full Markdown
  segment parser, judged not worth the time against Phases 6-9 still being fully unbuilt).

## Phase 6 — Screen context (SUPER+I) — DONE (image-support question answered empirically)
Built `quickshell/modules/screenctx/{ScreenState.qml, ScreenContext.qml}` — region-select via
`hyprshot -m region --raw` (grim/slurp aren't standalone-installed, only bundled inside hyprshot,
already the established convention for Print-key screenshots in this repo), routed by
`ai-workstation` state: gaming → tesseract OCR, silent (clipboard + notify, overlay never shows,
never steals game focus); docked → `qwen3-vl:4b` via direct Ollama `/api/generate`; undocked →
tesseract OCR shown in the overlay.

**Major finding**: empirically confirmed the pinned Goose 1.47.0 genuinely supports images —
`promptCapabilities.image: true` advertised, and a real base64 image block sent through
`session/prompt` was correctly processed (tested via the `claude-code` provider, which bypasses
the dead-KFD-blocked local GPU entirely — see below). This directly answers the task's own
"determine empirically" instruction and rules out "no image support" as a failure mode for the
docked path.

**Discovered a second escape hatch from tonight's GPU blocker**: `initialize`/`session/new` in
`goose acp` don't touch Ollama at all (pure protocol setup) — only `session/prompt` against the
`ollama` provider actually hits the dead GPU. The `claude-code` provider (already authenticated
on this machine) works completely normally right now, since it never touches local Ollama/ROCm.
Used this to live-verify the image-prompt pipeline above; did not have time to extend this to
re-verify chat overlay end-to-end tonight, but it's a real, available path if needed.

Not live-tested: the interactive region-select itself (needs a real mouse drag — genuinely a
physical-interaction gap) and the qwen3-vl:4b/Ollama path specifically (blocked by dead-KFD).
tesseract confirmed installed with real `eng` language data via a full build + `--list-langs`
check.

## Phase 7 — Voice conversation mode (SUPER+O) — DONE
Built `quickshell/modules/voice/{VoiceState.qml, VoiceOverlay.qml}`. Push-to-talk (hold Space),
Canvas-based reactive blob (deliberate fallback from the qsb shader path — see DECISIONS.md) bound
to a real `PwNodePeakMonitor` on the default audio source (confirmed real API against the
installed qmltypes, same pattern `Volume.qml` already uses for the bar). Reuses `GooseAcpSession`
rather than a third ACP implementation. Per-stage latency (record/transcribe/think/speak) measured
and shown after every turn. Kept `voice.nix`'s existing one-shot STT/TTS design rather than
building systemd services — a one-shot design already has zero idle memory footprint, which was
the actual goal behind the task's "idle timeout" ask; logged as a real trade-off in DECISIONS.md.

Verified: staging load (clean, real `chat/` module symlinked in for the `GooseAcpSession`
dependency), IPC toggle, no crash.

**Update, later in the night**: pre-downloaded both models (whisper `base.en`, 141MB; piper
`en_US-lessac-medium`, 63MB — fetching them needs none of the sudo/physical/auth/preference
conditions, so no reason to leave the first real SUPER+O press blocked on a cold download) and
mechanically verified both pipelines for real: `voice-transcribe` on a synthetic test WAV
genuinely loaded the model and produced a transcription (~1s total; correctly-if-amusingly
transcribed a sine tone as `(eerie music)`, which proves the pipeline works end to end, not that
recognition is perfect on non-speech input); `piper` directly synthesized real speech audio to a
WAV file successfully. `voice-models-ready` now returns exit 0. Deliberately did NOT trigger
actual audio playback (`pw-play`) — didn't want to make noise through the speakers at 3am.
**Still not live-tested**: the actual push-to-talk flow with a real mic and real Space keypress,
and real speech (as opposed to a synthetic test tone) — those need a human.

## Phase 8 — Mobile bridge rework — DONE (fan-out fixed, Serve blocked on browser auth)
Fixed the real bug: `goose_bridge.py` now holds ONE shared `goose acp` process for its whole
lifetime, broadcasting to every connected WebSocket client instead of spawning one process per
client. **Live-verified with two real simultaneous clients** — sent a request from client A,
confirmed both A and B received the byte-identical broadcast response; also verified client-drop
resilience and confirmed via logs the process starts exactly once across multiple connect/
disconnect cycles. Tested against the *actual* pre-existing live `qubi-bridge.service` (discovered
it was already running — home-manager switch happened once earlier tonight before this session
"woke up" — stopped it, tested my rewrite on the real port, restored the original after).

Investigated whether desktop+mobile could share one TRUE live session via `goose serve`'s native
HTTP surface — confirmed the surface is real (POST+SSE with `Acp-Connection-Id`, live-verified)
but found no live-fan-out/subscribe capability, and rearchitecting `GooseAcpSession.qml` to depend
on it was judged too risky against an already-proven-live desktop feature. Documented as a
deliberate scope decision, not an oversight — see DECISIONS.md/MOBILE_GUI_PLAN.md.

**Blocked on a genuine interactive-auth step**: `tailscale serve` requires a one-time browser
approval at a URL it prints (`login.tailscale.com/f/serve?node=...`) — confirmed live, this is
Tailscale's own tenant-wide Serve gate, not something scriptable. Built and ready:
`qubi-tailscale-serve` systemd service with the exact commands, documented prominently in
BLOCKERS.md. Made `mobile_gui.html`'s WebSocket URL derive from `location.protocol`/`host` instead
of a hardcoded IP so it doesn't break the moment Serve goes live.

PWA theming: found the color scheme already exactly matched `themes/ultraviolet/base16.yaml`
(verified byte-for-byte) from earlier work — fixed the one real gap, font-family (was plain
sans-serif, now tries the desktop's actual JetBrainsMono Nerd Font Mono first).

## Phase 9 — Integration and handoff — DONE
Re-ran `nix flake check`, `nixos-rebuild build --flake .#carbon`, and `qml-lint-repo` one final
time after every phase's changes — all clean (exit 0). Confirmed every module in `shell.qml` is
either pre-existing or carries a "built + staging-validated 2026-09-18" marker — none were
registered without going through the staging protocol first. Cleaned up a stale comment in
`shell.qml` that no longer matched reality (the 5 new modules aren't "placeholders" anymore).
Wrote `WAKEUP.md` — activation commands, a per-feature verification checklist with expected
results and failure recovery, rollback procedure, and BLOCKERS.md ranked by severity.

**Honest final accounting**: 8 of 9 phases are complete to the standard this file describes
(build-verified everywhere, live-verified wherever the dead-KFD state and physical-interaction
limits allowed). Phase 2 is the one genuinely incomplete phase — not for lack of trying, but
because the very thing it was benchmarking (local GPU inference) is what broke mid-benchmark.
That's flagged prominently, not buried.

## Environment notes for future-me
- `hyprctl` needs clean env (`env -i ...`) from this Bash tool — see Phase 0.
- `grim` is not installed standalone on this system — only `hyprshot` (wraps grim+slurp+hyprpicker,
  already used for the Print-key bindings in hyprland.nix). Phase 6 (screen context) should use
  `hyprshot -m output/window/region --raw`, not assume bare `grim`/`slurp` are on PATH.
- Quickshell live PID: check `pgrep -af quickshell` before any QML work; never edit
  `quickshell/modules/**` files that are actually imported by `shell.qml` without staging first.
- Disk: 69GB free at session start on `/`. Recheck before any further `ollama pull`.
