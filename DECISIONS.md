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
