# Qubi overnight build — BLOCKERS

Ranked by how much they hold back activation. Updated as discovered.
Night 1 (2026-09-18) blockers are archived at
`docs/history/BLOCKERS-2026-09-18.md`. This file now covers night 2
(`qubi/engine` branch) only.

## 1. gpt-oss:20b / devstral:24b isolated retest blocked by model-store permissions

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

---

*Night 1's blockers (dead-KFD reboot requirement, Tailscale Serve admin
approval) are both resolved per WAKEUP-2026-09-18.md and archived at
`docs/history/BLOCKERS-2026-09-18.md`.*
