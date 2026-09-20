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

## Heuristic router: verb-hit alone does NOT cross the heavy threshold
**Decided:** `score_prompt()` only routes straight to heavy on strong
syntactic signals (code fence +5, message >400 chars +3, file path mention
+2); a heavy-sounding verb ("refactor"/"implement"/etc.) alone contributes
just +1, nowhere near the threshold=5 cutoff.
**Why:** The task brief itself gives two examples that only both come out
correct under this reading: "a trivially easy prompt stays light" (score=0,
trivially satisfied either way) AND "a prompt like 'refactor the dock/undock
state machine into a single module' triggers an escalation_offer" -- an
offer can only fire from the LIGHT tier (only light has the escalate tool
attached), so this exact prompt must start light, not be pre-routed to
heavy. Since "refactor" is explicitly listed among 3a's own verb signals,
a naive "verb hit -> heavy" reading would send this prompt straight to
heavy and the escalation_offer would never fire -- contradicting the task's
own verification requirement. Weighting the verb as a minor contributor
(not a standalone trigger) is the only scoring scheme that satisfies both
examples simultaneously. Live-verified: this exact prompt scored 1 (light,
correct) and a real code-fenced version of a similar prompt scored 6
(heavy, correct) -- see PROGRESS.md Phase 3.
**Alternatives:** Any verb hit forces heavy directly (rejected: contradicts
the brief's own escalation_offer example). Verbs don't count at all
(rejected: then the heuristic does nothing beyond fence/length/path,
wasting the brief's own explicit mention of verb signals).
**To change it:** `engine/qubi_engine.py`, `HEAVY_VERBS` tuple and the
per-signal point values in `score_prompt()`.
**Confidence:** medium-high -- a genuine textual ambiguity in the brief,
resolved by requiring both of the brief's own worked examples to hold
simultaneously, then confirmed against real model behavior.

## Warm-up is a direct Ollama call, not a full ACP turn
**Decided:** `Engine.start()` warms the light tier's model via a raw
`POST /api/generate` (non-streaming, `keep_alive` from config), not by
spawning `goose acp` and running a real `session/prompt` turn.
**Why:** Measured live, in this engine's own first run: routing warm-up
through a full ACP turn took 54.5 seconds, because it waits for the model
to finish an entire reasoning pass on a throwaway prompt. What warm-up
actually needs -- weights resident in VRAM -- is the `prompt eval` phase,
which Phase 0's own `journalctl -u ollama` evidence already showed takes
low seconds even cold. Switching to a direct call dropped cold start to
4.5 seconds on the very next run, real numbers both times.
**Alternatives:** Keep routing warm-up through a real ACP turn but with a
shorter prompt (rejected -- thinking-token cost doesn't scale down much
with a shorter prompt, confirmed by Phase 0's own "ready" test already
being about as short as a prompt gets and still costing 17-36s).
**To change it:** `Engine.start()`/`Engine._ollama_warm()` in
`engine/qubi_engine.py`.
**Confidence:** high -- directly measured, not inferred.

## Claude tier default model: `"sonnet"`, not empty string
**Decided:** `tiers.claude.model` and `tiers.claude.cpu_model` both default
to `"sonnet"` in `qubi_config.py`.
**Why:** Confirmed live -- empty string makes `goose acp`'s `session/new`
fail outright (`Failed to resolve model: Configuration value not found:
GOOSE_MODEL`) when the per-tier isolated config doesn't otherwise supply
one, and even when the *base* config's stale top-level `GOOSE_MODEL:
"qwen3:4b"` leaks through as a fallback, every prompt then fails
("issue with the selected model (qwen3:4b)"). `claude --help` documents
`sonnet`/`opus`/`fable` as real model aliases; `sonnet` confirmed working
end-to-end (real streaming response from a real engine-spawned claude-tier
session).
**Alternatives:** A fully-qualified model id instead of the alias
(untested, alias confirmed working so no reason to chase this tonight);
leaving it empty and forcing every caller to set `GOOSE_MODEL` explicitly
(rejected -- defeats the point of a sensible tier default).
**To change it:** `engine/qubi_config.py`'s `DEFAULT_CONFIG["tiers"]
["claude"]["model"]`, or live via `qubi-config set tiers.claude.model
'"opus"'`.
**Confidence:** high -- directly measured.

## Claude tier vs. local tiers: capability gap table (not papered over)
**Decided:** Document the real, measured differences rather than assume
Phase 4a/4b's registration work made the claude tier fully equivalent to
the local tiers.

| Capability | light/heavy (ollama) | claude tier (via `goose acp` + claude-code) |
|---|---|---|
| Responds to prompts | yes | yes (confirmed, real streaming) |
| `escalate` tool | light only, by design | not attached (not in its extension list; also see below) |
| Skills (`.agents/skills/` via `.claude/skills/` symlinks) | goose reads `.agents/skills/` directly (Goose's own skills extension) | **not verified reachable from inside a goose-acp claude-code session** -- Phase 4b's live proof used the `claude` CLI directly, not through goose's bridge; not re-tested through the bridge specifically |
| `ask_user` / `notes-capture` MCP tools | reachable via Goose's own extension config (per-tier synthesized `config.yaml`) | **registered (user-scope AND project-scope, both tried) but not surfaced to the model at all** through `goose acp`'s claude-code bridge -- confirmed live, zero tool_call events across a full transcript where the model was explicitly instructed to use the tool. Directly querying the SAME registration via plain `claude -p` (no goose) DOES surface the tool (blocked only by an orthogonal permission-prompt gate, itself fixable) -- isolating the gap to goose's claude-code bridge specifically, not the MCP registration |
| Session continuity across a tier switch (`session/load`) | n/a (same process family) | **confirmed working** -- `qubi/set_tier` to claude, real `session/load` succeeded, real follow-on response streamed |
| Cost/latency | free, local, GPU/CPU-bound | Liam's subscription, network-bound, no local thinking-token tax (first token in ~2.3s vs. 17-36s+ for local reasoning models on trivial prompts) |

**Why this matters**: the escalation flow's `suggested_tier: "claude"`
path will currently get a real, fast, coherent response from Claude -- but
if that response needs to call `ask_user` or `notes-capture` (the whole
reason Phase 4c was called "the single most important verification
tonight"), it will currently fall back to asking in plain conversational
text instead of firing the real on-screen `AskUserDialog`. This is a real,
user-visible gap, not a subtle one.
**What's needed to actually close it** (not done tonight, out of tonight's
safe scope -- would mean digging into how `goose`'s claude-code provider
invokes the `claude` binary/SDK internally, likely via strings/behavioral
probing of the `goose-cli` binary itself, or filing/checking a Goose
upstream issue): determine whether goose's claude-code bridge invocation
can be made to pass through `--mcp-config`/equivalent, or whether it uses
the Claude Agent SDK in a mode that structurally can't load MCP servers at
all (in which case the real fix is architectural -- e.g. routing
escalated-to-claude ask_user needs through the engine's own permission
banner instead of relying on Claude's own tool-calling).
**Confidence:** high on the measurements; the "why"/root-cause of goose's
specific bridge behavior is not root-caused (would need source access or
much deeper probing) -- flagged as exactly that, not overclaimed.
