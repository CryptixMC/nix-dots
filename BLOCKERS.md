# Qubi overnight build — BLOCKERS

Ranked by how much they hold back activation. Updated as discovered.

## 1. eGPU is in the dead-KFD state RIGHT NOW — reboot required (2026-09-18 ~02:10 CDT)

**What I found**: partway through Phase 2's benchmark run, `qubi-health` (the CLI I built this
session) reported `DEAD-KFD-REBOOT-REQUIRED`. Independently confirmed:
- `lspci -d 1002:73bf` — the eGPU **is** physically present on the PCI bus.
- `rocminfo | grep -c "Device Type:.*GPU"` — **zero** GPU agents reported.
- `curl -X POST http://localhost:11434/api/generate ...` — hard-timed-out at 20s, no response at all.
- `systemctl status ollama.service` and `ollama ps` — both hang rather than returning.

This is **exactly** the failure mode TODO.md §7 documents from three separate incidents earlier
this project ("Found and fixed along the way", Phase 1a and the 2026-09-16 undocked-reliability
investigation): a crash or bad disconnect leaves `amdgpu` cleanly bound with a valid PCI BAR while
ROCm/KFD compute is silently dead, and any Ollama runner that was using it gets orphaned in an
unkillable state, which then makes anything that tries to enumerate the process tree
(`ollama ps`, `systemctl status`) hang too. **The only known fix is a full reboot** — not
something I can do (explicitly forbidden: `sudo`/`reboot`/`systemctl restart` are all off-limits).

**Most likely trigger**: this happened during Phase 2's benchmark sweep, specifically while
`gpt-oss:20b` was running its first cell (`append-naive`) — the exact model the task brief
flagged as having "documented Ollama/llama.cpp parsing bugs" around its harmony tool-call format.
I did not get a clean pass/fail verdict on gpt-oss:20b before the crash — **this is itself
suspicious enough that gpt-oss:20b should be treated as provisionally disqualified** until it can
be re-tested in isolation (its own throwaway `ollama serve` instance, not the live service) after
a reboot. Did not confirm this is the actual root cause (no crash log captured before I found the
dead state, and I can't get `journalctl` for the crash moment while `systemctl`/`ollama ps` are
both hung) — treat as a strong hypothesis, not a proven cause.

**What this blocks for the rest of tonight**: any feature that needs a real Ollama response
(chat overlay live-testing, clipboard transform's actual model call, Phase 6 vision routing,
Phase 7 voice, further Phase 2 benchmarking) cannot be live-verified against the docked GPU until
you reboot. I'm continuing with everything that doesn't need a live model response — QML
structure, MCP server protocol-level code, Nix builds/lint, non-inference plumbing — and will
flag each item that's build-verified-only-not-live-verified as I go.

**What you need to do**: reboot. After reboot, run `qubi-health` to confirm it prints `HEALTHY`
(or `EGPU-ABSENT` if undocked) before trusting any AI feature. Then re-run Phase 2's benchmark
(`~/qubi-staging/run-bench-matrix.sh`, resumable — already-labeled results in
`~/.local/share/goose-bench/results.jsonl` are skipped automatically) with extra caution around
`gpt-oss:20b` specifically — consider running just that model's cells first, in isolation, before
trusting it near anything else.

**Benchmark results collected before the crash**: none of *this session's* `docked-rep1-*` labels
completed (the first cell, gpt-oss:20b append-naive, is what triggered this) — check
`~/.local/share/goose-bench/results.jsonl` for the exact cutoff. The `docked-glm-4.7-flash-*`/
`docked-qwen3-coder-latest-*`/etc. rows already in that file are from a *prior night* (2026-09-17
timestamps, not tonight) and are unaffected/still valid.
