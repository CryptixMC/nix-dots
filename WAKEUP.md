# WAKEUP — Qubi engine build, night 2, morning activation guide

Branch: `main` (night 1's `qubi/overnight` and night 2's `qubi/engine` are both merged in — see
`git log --oneline` for the full per-phase commit history). Nothing pushed to `origin`. Read
`PROGRESS.md` for the full phase-by-phase log, `DECISIONS.md` for every call made on your behalf,
`BLOCKERS.md` for what's genuinely stuck.

**Top-line status**: all 10 phases of tonight's plan are complete, `nix flake check` and
`nixos-rebuild build --flake .#carbon` both pass clean, `qml-lint-repo` is clean. The engine
architecture itself (multi-tier daemon, routing, escalation, every client migrated onto it) is
real and live-verified tonight, repeatedly, against the actual running system — not just built.
But there is one real, severe bug found *by* tonight's own acceptance-suite work, fixed in source,
**not yet live**: see BLOCKERS.md #1 before trusting the light tier under real load.

---

## 1. Activation — run these in order

```bash
cd ~/nix-dots
git log --oneline -20          # see everything that happened tonight
nix flake check                # already passed tonight — re-confirm before switching
nixos-rebuild build --flake .#carbon   # already passed tonight — re-confirm
nh os switch                   # picks up nothing new system-level tonight, but confirm anyway
nh home switch                 # THIS is what actually matters tonight: qubi-engine.service picks
                                # up GOOSE_MAX_TOKENS + the theme-parsing fix, qubi-bench becomes
                                # available, notes-capture starts writing to the real vault
```

**Immediately after `nh home switch`**, restart the engine so it's running the just-switched
binary, not whatever was already running from before:
```bash
systemctl --user restart qubi-engine.service
qubi-bench acceptance --tier light    # should now complete cleanly within a bounded time —
                                       # if the escalate case still takes minutes, see BLOCKERS.md #1
```

---

## 2. Latency — before/after (Phase 6, full detail in `.agents/bench/2026-09-19-latency.md`)

| Point | Before (spawn-per-open) | After (engine-backed) |
|---|---|---|
| Ready-to-chat overhead | 170-190ms process spawn | **7-61ms** (connect→list→new, tier already warm) |
| Cold engine start → light ready | n/a (no engine) | **4.5s** |
| First-token latency (TTFT), light tier | 17.0-35.9s | **30.9-39.4s** (not improved — see below) |

**The honest finding**: the engine mechanics are a real win (spawn cost amortized away entirely),
but TTFT itself did **not** improve with the light tier's minimal 1-extension config — the
bottleneck was never tool-schema size, it's the model (`qwen3:4b`) reflexively "thinking" for
hundreds-to-low-thousands of tokens before answering even a trivial prompt.
`GOOSE_LOCAL_ENABLE_THINKING=false` only partially suppresses this (23.3s→17.0s, not to sub-2s).
Tested Ollama's own `think: false` parameter directly, bypassing Goose: **a real ~14x reduction**
(47.6s→3.4s) — Goose's env var does not correctly translate into this API parameter for the
ollama provider. This is the single highest-value follow-up for anyone touching Goose's own
provider integration; not fixable from this repo alone.

---

## 3. Acceptance results (Phase 9 — `qubi-bench acceptance --tier light`)

Gates are defined in `.agents/bench/gates.json`. Real live results tonight (against the
**unfixed** engine, before the GOOSE_MAX_TOKENS fix below went live):

| Gate | Result | Note |
|---|---|---|
| tool-format | verified correct via real engine logs (4 separate real escalate calls, all well-formed) | not captured through a single clean CLI run — see BLOCKERS.md #1 |
| no-tool | **PASS** (real, clean live run) | trivial prompt → zero tool calls, correct answer, 66s TTFT |
| escalation-accuracy | verified correct via real engine logs | same caveat as tool-format |
| append-vs-overwrite | **SKIP** | light tier has no file-mutation tools (`extensions: ["escalate"]` only) — by design |
| no-phantom-write | **SKIP** | same reason |
| latency | **FAIL** (honest, expected) | 17-66s measured vs. a 1500ms budget — see §2 above, this is the model's own reasoning overhead, not a config bug |
| game-qa | **SKIP** | not currently in a real gaming state (`/run/ai-workstation/state.json` says `docked`) — this CLI never writes that root-owned file to force one |

Re-run `qubi-bench acceptance --tier light` after `nh home switch` + engine restart for a genuinely
clean single-invocation result — full JSON lands at `~/.local/share/qubi-bench/acceptance-light.json`.

---

## 4. Resource footprint (Phase 7c, idle/light-warm snapshot)

| Component | RSS / accounted |
|---|---|
| `qubi-engine.service` | 169 MiB |
| each `goose acp` tier process | ~65-120 MB |
| `quickshell` (live shell) | ~184 MB |
| `ollama serve` (host RSS only — model weights are VRAM-resident) | ~40 MB |
| `qwen3:4b` (light tier), actual VRAM | 4.0 GB (`ollama ps`) |
| System total at snapshot time | 7.5 GiB / 38 GiB |

`keep_alive`/idle-reap gap (real, not fixed tonight): `tiers.<name>.keep_alive` in config.json is
only actually wired to Ollama for the light tier's own warm-up call — heavy/claude's `keep_alive`
values aren't enforced anywhere, and the engine's idle-reap never calls `ollama stop`, so a
VRAM-resident model outlives its tier process until Ollama's own 30-minute system default expires.

## 5. Model roster (Phase 7b — `qubi-models roster` / `qubi-models prune --dry-run`)

Declared roster: 5 models (3 tier models + `qwen3.6:latest` for docked/goose.nix + `qwen3-vl:4b`
for screen-context). `prune --dry-run` flags `devstral:24b`, `gpt-oss:20b` (Phase 0 benchmark
candidates, never adopted into real routing), and `nomic-embed-text:latest` (no code reference
found anywhere) as installed-but-undeclared. No deletion implemented — dry-run only, per instruction.

---

## 6. Verification checklist

| # | Feature | Trigger | Expected | If it fails |
|---|---|---|---|---|
| 1 | Engine health | `qubi-bench acceptance --tier light` (after switch+restart) | 7 gates, no unexpected FAIL beyond the known `latency` one | `journalctl --user -u qubi-engine.service` |
| 2 | Chat overlay | `SUPER+D`, send a message | real streamed reply through the engine socket (live-verified tonight: got a real "pong") | check `engineUnavailable`/the assistant-bubble error text; `systemctl --user status qubi-engine` |
| 3 | Escalation offer | ask something that clearly needs a rewrite/refactor across files | a real escalation happens (confirmed live 4x tonight) and a banner appears with 3 buttons (Escalate to Claude / Escalate to heavy / Stay on light) — the banner itself is only structurally verified tonight (clean reload, not visually screenshotted), first real visual test — but the turn may take a while until the GOOSE_MAX_TOKENS fix is live, see BLOCKERS.md #1 | if it hangs past a few minutes, `systemctl --user restart qubi-engine` |
| 4 | Bar status glyph | look at the bar (right side, before Network) | a "Q" glyph, purple when a tier is warm/active, dim when the engine's down, pink+blinking while warming | hover for the exact tier/model in the tooltip |
| 5 | Mobile GUI theming | open `mobile_gui.html` on the tailnet | dark Ultraviolet theme, matching the desktop's live theme | if colors look wrong, check `qubi/theme`'s real reply once the engine fix is live |
| 6 | Notes capture | `SUPER+N`, capture a note | lands in `~/Documents/Vault/Inbox/Qubi.md` (real Obsidian vault, not `.agents/inbox.md` anymore) | `qubi-notes-capture-mcp --cli --title x --summary y` directly |
| 7 | Model roster hygiene | `qubi-models prune --dry-run` | lists real installed-but-undeclared models with sizes | nothing to fix, this is informational only |
| 8 | Rollback path | `systemctl --user stop qubi-engine` while chat overlay is open | overlay shows a real "connection lost" error, not a hang; bar glyph dims | both **live-verified tonight** — see PROGRESS.md Phase 10 |

---

## 7. Rollback procedure if something breaks

1. `cd ~/nix-dots && git log --oneline` — find the last commit before whatever broke it.
2. `systemctl --user stop qubi-engine` restores the pre-engine world for the chat overlay: it'll
   show a real, clear "engine not running" error (live-verified tonight) rather than hang or crash.
3. To fully revert the client-side transport swap: `git checkout <pre-Phase-8a-commit> --
   quickshell/modules/chat/GooseAcpSession.qml` restores the old direct-`goose acp`-process
   design. Quickshell hot-reloads on file change — no restart needed to see the revert take effect.
4. `git checkout main -- quickshell/` (if `main` still has last night's known-good state at the
   time you're reading this) restores the entire pre-tonight shell.
5. None of tonight's NixOS/home-manager changes are destructive or remove anything a normal boot
   needs — everything is additive, `nix flake check`-clean, verified via `nixos-rebuild build`.
6. If `qubi-engine.service` itself is crash-looping: `journalctl --user -u qubi-engine.service`
   first: the two real bugs found and fixed tonight (theme-parsing, GOOSE_MAX_TOKENS) are the most
   likely causes of anything *new* going wrong tier-side; both are in `engine/qubi_engine.py`.

---

## 8. Decisions made on your behalf

Full detail and reasoning in `DECISIONS.md`. Flagged items worth reading first:
- Branch strategy (`qubi/engine` off `qubi/overnight`, later merged to `main`)
- Runtime config location (`~/.config/qubi/config.json`, not YAML/TOML)
- Heuristic router thresholds (verb-hit alone does NOT cross the heavy threshold)
- Claude tier default model (`"sonnet"`, not empty string)
- **Claude tier vs. local tiers: capability gap table** — the claude tier cannot currently trigger
  `ask_user`/`notes-capture` the way local tiers can (BLOCKERS.md #3) — read this before relying
  on Claude-tier escalation for anything that needs to ask you something mid-conversation.

New tonight, not yet in DECISIONS.md as a separate entry (see PROGRESS.md Phase 8a for the full
reasoning): free-form model/subagent switching in the chat overlay is now tier-based
(`qubi/set_tier`) rather than arbitrary provider/model pairs, since the engine owns each tier's
process now. See BLOCKERS.md #4 for what this means for the existing model-picker UI.

---

## 9. Blockers, ranked by how much they hold back

Full detail in `BLOCKERS.md`. Summary, most-blocking first:

1. **A rambling escalate turn can block an entire tier for everyone.** Fix already written
   (`GOOSE_MAX_TOKENS=4096` on the engine's tier processes, matching what `goose.nix`'s own CLI
   wrappers already do) but **not live** — needs `nh home switch` + an engine restart. Until then,
   a real escalation-triggering prompt on the light tier can hang that whole tier for 4+ minutes
   for every session using it, not just its own. This is the one item worth fixing before trusting
   the light tier under real multi-session load.
2. **`gpt-oss:20b`/`devstral:24b` isolated retest** — blocked by model-store permissions, carried
   over from earlier tonight, not urgent.
3. **`goose acp`'s claude-code bridge doesn't surface MCP tools to the model** — the claude tier
   can't trigger `ask_user`/`notes-capture` the way local tiers can; needs Goose source access or
   a structural workaround (routing through the engine's own permission-banner UI instead).
4. **Free-form model/subagent switching regressed by the engine architecture** — `switchModel` now
   only works for the 3 real tier models (routes to `qubi/set_tier`); `switchSubagentModel` has no
   engine equivalent at all. A UI decision for you: replace ChatOverlay.qml's model picker with a
   tier-based one, or lean on the new escalation-offer chip instead.

---

*Written last, as instructed. Everything above reflects what was actually run and observed
tonight, not what should theoretically work — see PROGRESS.md for the evidence behind each line.*
