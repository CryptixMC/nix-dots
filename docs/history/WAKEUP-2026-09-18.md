# WAKEUP — Qubi overnight build, morning activation guide

Branch: `qubi/overnight` (21 commits tonight, all on top of `main` @ 3e46106, nothing pushed,
nothing merged). Read `PROGRESS.md` for the full phase-by-phase log, `DECISIONS.md` for every
call made on your behalf, `BLOCKERS.md` for what's genuinely stuck.

**Top-line status**: 8 of 9 phases complete and build-verified. Phase 2 (model benchmark) is
genuinely blocked partway through — see BLOCKERS.md item 1, needs a reboot. Everything else is
either fully live-verified or build-verified-with-clearly-documented-gaps (see each phase's
PROGRESS.md entry for exactly which).

---

## 1. Activation — run these in order

```bash
cd ~/nix-dots
git checkout qubi/overnight     # if not already on it
nix flake check                 # should already pass — re-confirm before switching
nh os switch                    # zram, qubi-health, amdgpu params (mostly already live), sudo rules
nh home switch                  # qubi-* wrappers, mobile bridge services, hyprland keybinds, MCP servers
```

Both switches realize configs that were already fully `nix build`-verified tonight — this should
be fast (mostly activation scripts, not fresh compilation).

**Then, separately, because of BLOCKERS.md item 1**: reboot to clear the dead-KFD eGPU state
before trusting any local-model (Ollama) feature. Run `qubi-health` first — it must say `HEALTHY`
or `EGPU-ABSENT`, not `DEAD-KFD-REBOOT-REQUIRED`, before you rely on anything docked-GPU-related
below.

**Then, whenever convenient, a one-time browser step** (BLOCKERS.md item 2): visit the URL
`tailscale serve` prints (`https://login.tailscale.com/f/serve?node=...`) to enable Serve on this
tailnet, then either restart `qubi-tailscale-serve.service` or just let it run on next login —
it's already enabled and will start succeeding automatically the moment Serve is approved.

---

## 2. Verification checklist

One line per feature: how to trigger it, what you should see, what to do if it doesn't work.

| # | Feature | Trigger | Expected | If it fails |
|---|---|---|---|---|
| 1 | zram swap | `zramctl` | a zram0 device listed, ~50% of RAM | check `systemctl status zramswap` |
| 2 | qubi-health | `qubi-health` | `HEALTHY` (docked) or `EGPU-ABSENT` (undocked) | if `DEAD-KFD-REBOOT-REQUIRED`, reboot |
| 3 | Qubi renaming | `qubi-code --help`, `qubi-chat`, `qubi-claude`, `qubi-plan` | all resolve; old `goose-*` names still work as aliases | `which <name>` to check PATH |
| 4 | Model roster | `ollama list` | `gpt-oss:20b`, `devstral:24b`, `qwen3-vl:4b`, `nomic-embed-text` all present | re-run `ollama pull <name>` |
| 5 | Clipboard transform | copy some text, `SUPER+U` | overlay shows 8 actions; pick one, streamed result, auto-copied | check `journalctl --user -u qubi-bridge` isn't relevant here — check Quickshell's own log (`~/.local/state` or `/run/user/$UID/quickshell/by-id/<current>/log.log`) for `ClipboardTransform` errors |
| 6 | Ask-user MCP | ask Goose something genuinely ambiguous in a `qubi-code` session (must be `ollama` provider — `claude-code`/`claude-acp` bypass Goose's own extensions entirely, confirmed tonight, not a real test of this) | a real on-screen dialog appears (not a guess) | **not live-tested tonight** (needed a real ollama-driven LLM tool call, blocked by item 1) — first real test |
| 7 | Notes capture | `SUPER+N`, type a title+summary, click Capture | entry appended to `.agents/inbox.md` | check the CLI directly: `qubi-notes-capture-mcp --cli --title x --summary y` |
| 8 | Research recipe | `goose run --recipe ~/.config/goose/recipes/research-agent.yaml --params topic="..."` | real search + fetch + a new `.agents/inbox.md` entry | recipe itself validated (`goose recipe validate`); the actual search/fetch/capture chain wasn't live-run tonight |
| 9 | Skills | inside any `qubi-code`/goose session, `/skills` or just ask a nix-dots/QML/eGPU question | the model references real content from `.agents/skills/*/SKILL.md` | `goose skills list` should show 4 project skills — confirmed working tonight |
| 10 | Chat overlay basics | `SUPER+D` | markdown renders, timestamps show, thinking bubbles collapse/expand on click | all pre-existing + tonight's additions, live-verified for structure; full conversation needs item 1 fixed |
| 11 | Chat compare | `SUPER+SHIFT+D` | two independent panes, type once, both respond | build/staging-verified only — **not live-verified**, needs item 1 fixed |
| 12 | Screen context | select some on-screen text or a UI element, `SUPER+I`, drag-select a region | docked: a vision description; undocked: OCR'd text; gaming: silent clipboard-copy + notification, no overlay | needs a real mouse drag (can't be scripted) — this is the very first real test |
| 13 | Voice mode | `SUPER+O`, hold Space, say something, release | blob reacts to your voice while held; after release: transcript, response, spoken reply, latency shown | models are already pre-downloaded and both pipelines mechanically verified tonight (whisper + piper each tested directly, no cold-start delay expected) — this is the first test with a *real mic and real speech* specifically |
| 14 | Mobile GUI (phone) | on your phone (same tailnet), visit `http://100.66.17.61:8901/mobile_gui.html` | session list loads, chat works | if two phones (or a phone + desktop workaround) connect, they should now share the SAME live session — this fan-out fix is live-verified server-side tonight, not yet from a real phone |
| 15 | Mobile GUI HTTPS | after the Tailscale Serve browser step above | `https://<tailnet-hostname>/mobile_gui.html` loads, mic-dependent features work | if Serve was approved but this doesn't work, check `tailscale serve status` and `systemctl --user status qubi-tailscale-serve` |

---

## 3. Rollback procedure if the shell breaks

The live shell survived every single change made tonight (confirmed via its own hot-reload log
after every edit — see PROGRESS.md). If something still goes wrong after a switch:

1. `cd ~/nix-dots && git log --oneline` — find the last commit before whatever broke it.
2. `git checkout <that-commit> -- quickshell/` (or the specific file) to revert just the shell,
   without touching Nix-level config.
3. If Quickshell is still crash-looping, kill it and relaunch manually:
   `pkill quickshell; quickshell -p ~/nix-dots/quickshell &` — watch its log
   (`~/.local/state/quickshell/...` or check `journalctl --user` for however it's normally
   launched) for the actual QML error.
4. Full nuclear option: `git checkout main -- quickshell/` restores the exact pre-tonight shell.
5. None of tonight's NixOS/home-manager changes (zram, qubi-health, MCP servers, etc.) touch
   anything that would prevent a normal boot even in the worst case — this was all additive,
   `nix flake check`-clean, non-destructive config.

---

## 4. Decisions made on your behalf

Every non-trivial call is in `DECISIONS.md` with why, alternatives considered, and exactly which
file/line to change if you disagree. Flagged **low-confidence** items worth reading first:
- Notes-capture target (`.agents/inbox.md` vs. your real `~/Documents/Vault`)
- Devstral tag confirmation (medium confidence, not independently re-verified against Ollama's
  live library index)

Everything else is medium-to-high confidence with real evidence behind it (live tests, build
verification, or direct empirical investigation — see PROGRESS.md for what was actually run).

---

## 5. Blockers, ranked by how much they hold back

Full detail in `BLOCKERS.md`. Summary, most-blocking first:

1. **Dead-KFD eGPU state** — blocks essentially all local-model (Ollama) functionality: the rest
   of Phase 2's benchmark, live chat overlay testing, docked screen-context vision, voice mode's
   LLM step if you don't have a mic handy to test with claude-code instead. **Fix: reboot.**
2. **Tailscale Serve disabled tenant-wide** — blocks HTTPS for the mobile GUI (mic access, PWA
   install quality). **Fix: one browser approval**, URL is in BLOCKERS.md and gets printed by
   `tailscale serve` itself.
3. Smaller, non-blocking gaps are noted inline in PROGRESS.md per phase (e.g. per-fenced-code-
   block copy in the chat overlay, systemd-service-ification of voice's STT/TTS) — none of these
   block activation or core functionality, just possible future polish.

---

*Written last, as instructed. Everything above reflects what was actually run and observed
tonight, not what should theoretically work — see PROGRESS.md for the evidence behind each line.*
