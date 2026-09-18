# Qubi overnight build — DECISIONS

Format: topic / decided / why / alternatives / how to change / confidence.

## Working branch strategy
**Decided:** Single branch `qubi/overnight`, sequential commits, no per-module branches.
**Why:** Task instructions specify one branch. Earlier scaffolding comments (shell.qml,
ThemeDefaults.qml) mention "parallel agent branches" like `qubi/clipboard`/`qubi/voice` — that
implies a multi-agent-branch strategy that was never actually executed (only the placeholder
comments exist, no such branches in `git branch -a`). Not resurrecting that model — one agent,
one branch, sequential phases is simpler to reason about and matches the explicit instruction.
**Alternatives:** Per-module branches merged at the end.
**To change it:** Just branch off `qubi/overnight` per module and merge manually later.
**Confidence:** high (explicit instruction).

## Resuming in-progress work instead of restarting Phase 1
**Decided:** Treat the uncommitted working-tree state found at session start as legitimate prior
progress (not stray/corrupted state) and build on it rather than reverting and redoing.
**Why:** `git reflog` is clean (no lost commits), the diffs are internally consistent, well-commented,
dated today, and match the task's own Phase 1 checklist near-exactly — this is unmistakably an
earlier pass at this same task. Reverting and redoing would waste real model-pull time (the 4
models already pulled took the bulk of Phase 1f's wall-clock) and risk contradicting decisions
already reasoned through in-place (e.g. the qwen3.6-vs-qwen3:4b ad-hoc-chat default flip, done via
live ACP testing earlier tonight).
**Alternatives:** `git checkout -- .` and start clean.
**To change it:** `git diff HEAD` on each touched file shows exactly what to revert if any of it
turns out wrong.
**Confidence:** high.

## SUPER+X already taken — clipboard uses SUPER+U instead
**Decided:** Keep the prior session's substitution: clipboard transform is `SUPER+U`, not
`SUPER+X` as the master task literally specified.
**Why:** `SUPER+X` was claimed by the extensions/MCP manager in commit `445dc88` (2026-09-17,
before tonight's task started). The task's own safety section says to verify each keybind is
actually free — U was free, X wasn't. Following the letter of "SUPER+X" would silently break an
already-shipped, working feature.
**Alternatives:** Move the extensions manager off SUPER+X instead (rejected — that's a shipped,
tested feature; the newer unbuilt feature should yield the slot, not the reverse).
**To change it:** `modules/home-manager/wm/hyprland.nix`, the `mainMod + U` bind for
`clipboard transform`.
**Confidence:** high.

## Devstral tag: `devstral:24b`, not "Devstral Small"
**Decided:** Use `devstral:24b` as pulled (already present in `ollama list`).
**Why:** Ollama's library only publishes Devstral under the `devstral` repo name; `24b` is the
only/default size tag (there is no separate "Devstral Small" library entry — "Small" is Mistral's
own model-family marketing name for the 24B parameter count, not a distinct Ollama tag). Already
pulled by the prior session under this tag.
**Alternatives:** None found on Ollama's library under a different tag.
**To change it:** `ollama pull devstral:<other-tag>` if a different quantization is wanted later.
**Confidence:** medium (didn't re-verify against Ollama's live library index this session — trusting
the prior session's pull, which is currently `ollama list`-confirmed present and 14GB, a plausible
size for a 24B Q4-class quant).

## Clipboard transform: disabled entirely while gaming, not routed to a smaller model
**Decided:** When `/run/ai-workstation/state.json`'s `state == "gaming"`, the overlay shows
"disabled while gaming" and does not attempt any inference at all — it never falls back to a
tiny/CPU model.
**Why:** Matches Phase 6's own explicit principle (never load even a small model onto the game's
GPU). A clipboard-transform request is rare enough mid-game that losing availability there is a
much smaller cost than a frame hitch from contending inference, however brief.
**Alternatives:** Route to OCR-tier/CPU-only inference during gaming, like Phase 6 does for vision.
Rejected — clipboard transform is pure text, so "CPU-only" would just mean "slow," not
"differently-capable," and slow-but-contending is still contending.
**To change it:** `quickshell/modules/clipboard/ClipboardTransform.qml`, the `gamingCheckProcess`
handler — remove the early return on `gaming === true`.
**Confidence:** medium.

## Clipboard transform model: whatever ai-workstation.nix currently routes, falling back to qwen3:4b
**Decided:** Reads the model name straight out of `/run/ai-workstation/state.json` (same value the
rest of the system already routes to); falls back to `qwen3:4b` if the state file is missing or
unreadable.
**Why:** A raw `/api/generate` call has zero tool-calling surface — the qwen3:4b-vs-qwen3.6
reliability gap documented in `goose.nix` (tonight, ACP tool-use specific) doesn't apply here, so
there's no reason to hardcode a different model than whatever's already resident for the current
dock/gaming state. Falling back to qwen3:4b (not qwen3.6:latest) specifically when the state file
is absent matches this feature's own latency preference (clipboard transforms should feel instant)
over the ACP chat default's reliability preference.
**Alternatives:** Always use a fixed fast model regardless of routing state (rejected — would load
a second model into VRAM/RAM alongside whatever's already resident, doubling memory pressure for
no real benefit when docked).
**To change it:** `ClipboardTransform.qml`'s `gamingCheckProcess.stdout.onStreamFinished`.
**Confidence:** medium.

## Clipboard oversized cap: 8000 characters
**Decided:** Clipboard content over 8000 characters shows an "too large" message instead of
attempting a transform.
**Why:** Keeps a single request comfortably inside even the smallest routed model's
`OLLAMA_CONTEXT_LENGTH=16384`-token budget (see TODO.md §7) after prompt-template overhead, without
needing to know which model is currently active. 8000 chars is roughly 2000 tokens of English
prose — generous for "a paragraph or a few," which is this feature's actual use case.
**Alternatives:** Size the cap dynamically off the currently-routed model's real context window.
Rejected as unnecessary complexity for a feature whose whole point is quick snippets, not documents.
**To change it:** `ClipboardState.qml`'s `maxChars` property.
**Confidence:** medium.

## Notes-capture target: `.agents/inbox.md`, NOT the real Obsidian vault
**Decided:** `notes-capture` appends to `~/nix-dots/.agents/inbox.md`, not
`~/Documents/Vault` (the real, actively-used Obsidian vault I found — confirmed real via its
`.claude`/`.claudian` dirs, as opposed to `~/Documents/ProtonSyncTestVault`, which is clearly just
a test vault: minimal content, nothing but a README, untouched since July).
**Why:** The task's own instructions say to default to `.agents/inbox.md` if the vault target is
ambiguous, and it genuinely is — the real vault has no established inbox/daily-notes/capture
folder convention (just a stray `Untitled.md` and `testing.html` at its root). Auto-writing into
someone's actual personal knowledge vault with a folder structure they never chose is a much
worse mistake to make wrong than under-delivering into a repo-local scratch file — this is
explicitly flagged **low confidence**, not a considered final answer.
**Alternatives:** Write into `~/Documents/Vault/Inbox/` or `~/Documents/Vault/Qubi Captures.md`
directly.
**To change it:** `mcp-servers/notes_capture.py`'s `VAULT_PATH` constant — point it at
`~/Documents/Vault/<wherever you actually want captures to land>`.
**Confidence:** low — this is exactly the kind of subjective-preference call flagged as something
only Liam can make; flagging prominently rather than guessing his vault's organization.
