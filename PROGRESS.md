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

## Phase 2 — qubi-engine daemon

(not started)

## Phase 3 — Routing + escalation

(not started)

## Phase 4 — Claude tier tooling

(not started)

## Phase 5 — Gaming CPU-only

(not started)

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
