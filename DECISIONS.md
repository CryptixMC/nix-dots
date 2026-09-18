# Qubi engine build — DECISIONS (night 2, branch `qubi/engine`)

Format: topic / decided / why / alternatives / how to change / confidence.
Night 1's decisions are archived at `docs/history/` alongside its PROGRESS/
BLOCKERS/WAKEUP files and remain in force unless superseded below.

## Branch strategy: `qubi/engine`, off `qubi/overnight`
**Decided:** New branch per tonight's explicit instruction, sequential
commits, no push/merge.
**Why:** Task instruction, verbatim.
**Confidence:** high.

## Phase 0 benchmark matrix: abbreviated, not the full rep1/rep2/rep3 x 5-model sweep
**Decided:** Did not re-run the full `run-bench-matrix.sh` (3 reps x 5 models
x 3 shapes) tonight. Triaged last night's contaminated results, attempted
(and hit a real, logged blocker on) the specifically-called-out gpt-oss:20b
isolated retest, then moved to the actual architecture work.
**Why:** The task brief itself frames tonight as "ARCHITECTURE, not UI" and
explicitly deprioritizes Phase 2 relative to Phases 1-10's engine/routing
work ("Leave ai-workstation.nix's model choices alone unless the data is
unambiguous" — implying the benchmark is confirmatory, not gating). The full
matrix costs hours of wall-clock (each gpt-oss/devstral cell alone was
90-110 minutes on prior nights) that directly competes with the ten phases
that are tonight's real deliverable. The docked default the whole night's
routing design depends on (`qwen3:4b`) is already benchmark-clean from
2026-09-17, unaffected by any of this.
**Alternatives:** Run the full matrix first, accepting the ai-workstation.nix
gate would go unresolved for many hours before Phase 1 could even start.
**To change it:** `~/qubi-staging/run-bench-matrix.sh` is resumable by label
and already skips completed cells — just re-run it.
**Confidence:** medium-high — a scope call under explicit "work through all
ten phases" pressure, not a quality judgment; flagged clearly rather than
silently skipped.

## Runtime config location: `~/.config/qubi/config.json` (not YAML, not TOML)
**Decided:** Plain JSON, matching the task's own instruction verbatim.
**Why:** Task brief specifies the exact path and format. JSON also matches
what `qubi-config` (Phase 1's CLI) and the engine (Python) both parse
natively with zero extra dependencies, and matches the PWA's `qubi/theme`
consumer (Phase 2g) which is JS reading JSON directly.
**Confidence:** high (explicit instruction).
