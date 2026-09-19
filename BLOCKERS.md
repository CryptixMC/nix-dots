# Qubi overnight build — BLOCKERS

Ranked by how much they hold back activation. Updated as discovered.
Night 1 (2026-09-18) blockers are archived at
`docs/history/BLOCKERS-2026-09-18.md`. This file now covers night 2
(`qubi/engine` branch) only.

## ~~1. A rambling escalate turn can block an entire tier for everyone~~ — RESOLVED, live-verified

**Fixed and confirmed live** (`nh home switch` + `systemctl --user
restart qubi-engine.service`, both run). Re-tested the exact scenario
below against the real, now-running engine: the same escalate-triggering
prompt still produced a correct escalate call (~41s, normal range), and
a totally unrelated `session/new` sent immediately afterward — which
previously took 200+ seconds and timed out — now returns in **0.05s**.
`GOOSE_MAX_TOKENS=4096` genuinely fixed the root cause: bounding
generation length means the turn actually terminates instead of the
model rambling for minutes, so the tier's single-flight `goose acp`
process frees up almost immediately. Original write-up kept below for
the record.

<details>
<summary>Original finding (now resolved)</summary>

**What I found**: building and live-running Phase 9's acceptance suite
(`qubi-bench acceptance --tier light`) surfaced a real, severe bug —
confirmed 4 separate times, not a one-off: when the light tier's model
correctly calls the `escalate` tool (real, well-formed calls every time:
non-empty `reason`, valid `suggested_tier`), it does NOT reliably stop
generating afterward despite `escalate.py`'s own explicit instruction
("Stop here and wait — do not keep answering"). The underlying `goose
acp` process then kept running for 4+ minutes past the tool call in
every observed case. Because this tier's single `goose acp` process
serializes all work — confirmed live: a totally unrelated session's
plain `session/new` blocked 200+ seconds behind another session's
still-running turn — one such rambling turn blocks the ENTIRE light
tier for every session, not just its own. `session/cancel`, sent as
soon as the escalate signal was captured, did not free the tier up
either (checked twice, both times a subsequent fresh `session/new`
still hung).

**What this blocks**: this is directly user-facing. If Liam asks the
light tier something that trips escalation during real use, his own
chat overlay (or anyone else's concurrent session on the light tier)
would show "qubi is thinking…" for minutes with no way to unstick it
short of restarting `qubi-engine.service`.

**Root cause identified, fix already written**: `TierProcess
.ensure_started()` in `engine/qubi_engine.py` never set
`GOOSE_MAX_TOKENS` for the tier's spawned `goose acp` process — every
one of `goose.nix`'s own CLI wrappers (`qubi-code`, `qubi-claude`)
already sets `GOOSE_MAX_TOKENS=4096` for exactly this class of runaway-
generation bug, but the engine's tier processes never inherited it.
Added the same value with the same rationale. **Not yet live** — the
running `qubi-engine.service` is a nix-store snapshot from the last real
`home-manager switch` (this build's own rule against running `switch`
unsupervised), so this fix needs one before it's actually in effect.

**What you need to do**: run a real `home-manager switch` (or `nh home
switch`) to pick up the fix, then re-run `qubi-bench acceptance --tier
light` — the escalate case should now resolve within a bounded time
instead of hanging for minutes. If it's still slow after that, the next
thing to check is whether `GOOSE_MAX_TOKENS=4096` is too generous a cap
for this specific failure mode (i.e. the model reasoning past 4096
tokens before ever calling the tool, not just rambling after it) —
`qubi-bench`'s own output JSON (`~/.local/share/qubi-bench/acceptance-
light.json`) records the real per-case `ttft_ms` and `completed` flags
needed to tell those two failure modes apart.

</details>

## 2. gpt-oss:20b / devstral:24b isolated retest blocked by model-store permissions

**What I found**: `qubi-health` reports `HEALTHY` tonight (the eGPU recovered
after last night's reboot) — the intended path was to retest `gpt-oss:20b`
"FIRST and ALONE in a throwaway `ollama serve` on port 11435" before trusting
it near anything else, since it's the prime suspect for last night's dead-KFD
crash (see `.agents/bench/2026-09-19-roster.md` for the full triage of last
night's contaminated results). Attempting that:

```
OLLAMA_HOST=127.0.0.1:11435 OLLAMA_MODELS=/var/lib/ollama/models ollama serve
-> Error: mkdir /var/lib/ollama: file exists: ensure path elements are traversable
```

`ollama.service` runs as a dedicated `ollama` system user
(`systemctl show ollama.service -p User -p Group` -> `User=ollama
Group=ollama`); `/var/lib/ollama/models` is not readable by `cryptix`. A
throwaway instance can't read the already-pulled model blobs without `sudo`
(explicitly forbidden tonight) or a NixOS-level permission change (also
requires a switch, out of scope tonight).

**What this blocks**: re-verifying gpt-oss:20b and devstral:24b at all — both
remain formally unverified. Does NOT block tonight's actual architecture work
(engine, routing, Claude tier) since the routing design uses the already-clean
`qwen3:4b` docked default, not either of these.

**What you need to do**: either (a) run the throwaway-instance retest yourself
with `sudo`, or (b) apply a permission fix so `cryptix` (or a shared group) can
read `/var/lib/ollama/models` without sudo, so this pattern works
unattended next time — worth doing regardless of tonight's blocker, since
"isolate a risky model in a throwaway instance" is exactly the safety pattern
TODO.md already established as the right one.

## 3. `goose acp`'s claude-code bridge doesn't surface MCP tools to the model

**What I found**: registered `ask-user`/`notes-capture` as real MCP servers
for the `claude` CLI at both user-scope (`claude mcp add --scope user`,
confirmed `√ Connected`) and project-scope (`.mcp.json`, this repo). A
direct `claude -p` session sees and attempts to call `ask_user` (blocked
only by an unrelated, separately-fixable permission-prompt setting). But a
`goose acp` process with `GOOSE_PROVIDER=claude-code` -- the actual pathway
the engine's claude tier uses -- never attempts any tool call at all when
explicitly instructed to use `ask_user`; it just answers in plain text.
Confirmed by inspecting a full real session transcript through the real
engine: zero `tool_call` notifications anywhere in it.

**What this blocks**: the claude tier cannot currently trigger the real
on-screen `AskUserDialog` (or `notes-capture`) the way the local tiers can.
An escalated-to-claude conversation that needs to ask Liam something will
currently just ask in plain chat text instead.

**What you need to do**: this needs someone with either Goose's source or
much deeper black-box probing of the `goose-cli` binary's claude-code
provider integration to determine whether it can be made to pass through
MCP config to the underlying `claude` invocation, or whether a structural
workaround is needed (e.g. routing escalated-tier `ask_user`-shaped needs
through the engine's own permission-banner UI instead of relying on
Claude's own tool-calling for this one case). Full capability table and
the two-different-outcomes evidence: `DECISIONS.md`, "Claude tier vs.
local tiers: capability gap table."

## 4. Free-form model/subagent switching regressed by the engine architecture

**What I found**: `GooseAcpSession.qml`'s pre-engine `switchModel`/
`switchSubagentModel` worked by restarting *our own* `goose acp` process
with `GOOSE_PROVIDER`/`GOOSE_MODEL` env vars overridden. Now that
qubi-engine owns each tier's `goose acp` process (the whole point of
Phase 2/3's design), that process is no longer ours to restart, and the
engine exposes no per-request provider/model override — confirmed by
reading `qubi_engine.py`'s `_handle_qubi_method` in full: its complete
method list is `qubi/status`, `qubi/theme`, `qubi/session_list`,
`qubi/subscribe`, `qubi/set_tier`, nothing else.

**What this blocks**: `switchModel` now only works for the 3 real tier
models (routes to `qubi/set_tier` via a live `qubi/status`-sourced
model->tier table) — picking any other model (e.g. goose.nix's docked
`qwen3.6:latest`, which predates the engine and isn't any tier's model)
fails with a real, visible `sessionFailed` error instead of silently
doing nothing. `switchSubagentModel` has no engine equivalent at all (no
per-tier subagent concept exists) and always fails now.

**What you need to do**: decide whether ChatOverlay.qml's model/subagent
picker UI (the `modelConfigOption.options` dropdown, sourced from
whichever tier's own ACP `configOptions` happen to be exposed) should be
replaced with a tier-based picker (light/heavy/claude, i.e. exactly the
3 real choices `qubi/set_tier` supports) or removed in favor of the
escalation-offer chip (Phase 8a's own new UI) as the primary way to
change models mid-conversation. Not fixed tonight — this needs a real UI
decision, not a silent code patch. Full technical detail: `PROGRESS.md`,
Phase 8a.

## 5. Undocked, the light tier is slow enough that the model choice needs revisiting

**What I found**: three real undocked bugs are now fixed (ollama never
being restarted after an eject; the engine having no concept of
"undocked" at all; undock silently switching the live chat session to
the heavy tier — see the `fix qubi undocked` commit). With all three
fixed the undocked path *works*, but measured live on this box it is
still slow enough to be worth a deliberate decision rather than a silent
default:

| | docked (eGPU) | undocked (CPU) |
|---|---|---|
| `qwen3:4b` generation | 81 tok/s | **5.3-10.8 tok/s** (see note) |
| trivial turn ("Say exactly: pong") | a few seconds | **3m34s / 1544 tokens** |

(Light-tier startup *was* 19-60s undocked and is now 4.2s cold — that
one turned out to be a real bug, not CPU slowness: the Ollama warm-up
call generated a full reply instead of one token and blew its own 60s
timeout every time. Fixed, not a blocker.)

The CPU figure is a range because it is strongly load-dependent, which
matters for expectation-setting: 10.8 tok/s was measured on a quiet
system, 5.3 tok/s with an ordinary desktop session running (Discord
alone was taking ~40% of a core). It also degrades within a single long
generation as the KV cache grows. Assume the low end in practice.

Worth recording since it was checked and is easy to assume otherwise:
the `cpu_model` tag is **not** responsible for any of the slowness. A
controlled A/B on identical prompt/seed/length measured `qwen3:4b` at
5.37 tok/s and `qwen3:4b-cpu` at 5.25 tok/s — the `num_gpu 0` pin costs
nothing, it just makes explicit what Ollama would fall back to anyway.

The token count is the surprising part and it is *not* a config bug.
qwen3:4b narrates its reasoning as ordinary visible content no matter
what: `GOOSE_LOCAL_ENABLE_THINKING=false` is set by the engine, and
Ollama's own `think: false` was tested directly — both only move that
text out of the `thinking` field and into the answer. qwen3's documented
`/no_think` prompt switch merely halves it (196 -> 104 tokens on the
same prompt) and the model then narrates *about* the switch ("there is a
note `/no_think` which we should ignore"). So ~1500 tokens for a trivial
prompt is simply what this model does; on the GPU that is a few seconds
and nobody notices, on CPU it is three and a half minutes.

Mitigated but not solved: `GOOSE_MAX_TOKENS` is now hardware-scaled
(4096 docked, 2048 CPU-only), which bounds the *worst* case to ~5 min
instead of 9+. It cannot fix the typical case, because the typical case
is already ~1500 tokens — capping below that would truncate normal
replies rather than runaway ones.

**What this blocks**: nothing hard — undocked qubi answers correctly,
just slowly. But "ask a quick question on battery" is not really viable
at these numbers, and the light tier's model is currently hardcoded to
`qwen3:4b` in `~/.config/qubi/config.json` regardless of dock state.

**What you need to do**: this is a model-roster call, not a code patch,
which is why it is written up rather than fixed. The engine already has
the mechanism — each tier carries a separate `cpu_model` tag and the
engine now selects it correctly whenever the state is undocked or
gaming, so pointing the light tier at a different *model* when on CPU is
a one-line config change (`tiers.light.cpu_model`). The open question is
what to point it at. Worth noting the two candidates already measured in
this repo disagree with each other: `ai-workstation.nix`'s own
`undockedModel` comment picked `qwen3-coder:latest` for exactly this
role after CPU-only testing (5/6 real tasks, 71-928s — slow but
tool-call-reliable), while the light tier was later set to `qwen3:4b`
for docked speed (81 tok/s) without anyone re-measuring it on CPU. A
terser small model, or a `-cpu` Modelfile variant with a system prompt
that suppresses the narration, are the other obvious directions.

---

*Night 1's blockers (dead-KFD reboot requirement, Tailscale Serve admin
approval) are both resolved per WAKEUP-2026-09-18.md and archived at
`docs/history/BLOCKERS-2026-09-18.md`.*
