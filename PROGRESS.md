# Qubi overnight build — PROGRESS

Branch: `qubi/overnight` (off `main` @ 3e46106). Started 2026-09-18 ~01:50 CDT.

**Read before resuming**: this is a *resumption*, not a fresh start. When this session picked up,
`main`'s working tree already had substantial uncommitted Phase 1 work sitting in the index —
rebrand to Qubi, zram.nix, qubi-health.nix, amdgpu runpm/aspm params (already present, older),
hyprland keybinds reserved (U/I/O/N/SHIFT+D), theme tokens reserved, model pulls done (gpt-oss:20b,
devstral:24b, qwen3-vl:4b, nomic-embed-text — pulled ~21-25min before this session started), mobile
bridge packaged as a systemd user service. No commits were lost (checked `git reflog` — clean).
This was very likely an earlier pass of this exact overnight task in the same wall-clock night,
interrupted (context compaction or session boundary) before it committed anything or wrote these
log files. Read `TODO.md` §7 in full before assuming anything is unbuilt — it's an extremely
detailed, dated log of everything done on this project through 2026-09-17, including hard-won
findings (tool-calling reliability per model, context-length bugs, power-profile CPU throttling,
dock/undock sync bugs) that would be wasteful to rediscover.

## Phase 0 — Orientation — DONE 01:55
- Read TODO.md (full, 350 lines), AGENTS.md, MOBILE_GUI_PLAN.md, README.md (no Qubi/goose content —
  pure desktop-shell doc, not touched by this task).
- `df -h /`: 69GB free of 672GB (90% used). Above the 60GB floor — not a blocker, but model pulls
  eat into it fast; watch before pulling anything else large.
- Confirmed live Quickshell (PID 4588) running, no crash-relevant journal entries.
- **Found and fixed a real gotcha**: my Bash tool's inherited `LD_LIBRARY_PATH` includes a stray
  `gcc-15.3.0-lib` that breaks `hyprctl` (GLIBCXX version mismatch) when called directly from this
  shell. Workaround confirmed live: `env -i HOME=$HOME XDG_RUNTIME_DIR=/run/user/1000
  HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl ...` — clean env sidesteps it. Use this pattern for any
  hyprctl call from a Bash tool call for the rest of this session.

## Phase 1 — Rebrand + system modules
- [x] 1a rebrand — already done pre-session: user-facing strings say "qubi" (chat overlay "message
      qubi…", session-load error mentions qubi-code), script names renamed with `qubiAliases`
      backward-compat shims for old names, engine internals (GOOSE_* env vars, `goose acp`, `goose`
      binary, nixpkgs attrs) correctly left alone. Verified via grep — no stray `goose-*` script refs
      outside legitimate engine/env-var/debug-log context.
- [x] 1b zram — `modules/nixos/services/zram.nix` exists (50%, zstd), imported in
      `hosts/carbon/configuration.nix`.
- [x] 1c amdgpu runpm/aspm — already present in `amd.nix` from a prior session (`amdgpu.runpm=0`,
      `amdgpu.aspm=0`, `pcie_aspm=off`, kernel pinned `linuxPackages_6_18`). Did NOT re-derive
      whether 6.18.50 carries the 2026 kfd-surprise-disconnect/runtime-PM patches — no changelog
      access to confirm kernel-patch provenance offline; the existing runpm=0 workaround makes it
      moot either way (compute never attempts runtime PM regardless of whether the kernel fix
      landed). Documented as-is rather than guessing.
- [x] 1d qubi-health.nix — exists, 5-min timer, advisory-only (rocminfo vs lspci mismatch →
      hyprctl notify, never kills/restarts). **Gap found**: master task asked for a `qubi-health` CLI
      printing HEALTHY/DEAD-KFD-REBOOT-REQUIRED/WEDGED-RUNNER/EGPU-ABSENT — the existing module only
      has the systemd timer script, no standalone CLI and no D-state-wedged-runner detection. Added
      both (see commit).
- [x] 1e sleep hook — `ai-workstation-suspend-evict` in `ai-workstation.nix` (evicts loaded Ollama
      models before suspend, `|| true` throughout, bound to `sleep.target`). Already done.
- [x] 1f model pulls — gpt-oss:20b, devstral:24b, qwen3-vl:4b, nomic-embed-text all present in
      `ollama list` (pulled ~21-25min pre-session). Devstral tag: `devstral:24b` — this **is** the
      correct/only Devstral Small tag on the Ollama library (no separate "Small" suffix tag exists).
- [x] 1g keybinds reserved — U/I/O/N/SHIFT+D added to hyprland.nix with graceful-fail IPC calls
      (target doesn't exist yet → "Target not found", exit 0, confirmed by prior session's comment).
      NOTE: master task said SUPER+X for clipboard, but SUPER+X was already taken by the extensions
      manager (`445dc88`) — prior session correctly substituted SUPER+U instead and documented why.
      Keeping this deviation (logged in DECISIONS.md).
- [x] 1h theme tokens + host imports — ThemeDefaults.qml has placeholder token families
      (clipboard/screenctx/voice/notes/compare), hosts/carbon/*.nix import zram+qubi-health.
      `qubi-mcp.nix` import commented out in home.nix (module doesn't exist yet — Phase 4 will
      create it and uncomment).
- [ ] 1i `nix flake check` + `nixos-rebuild build --flake .#carbon` — running now.

*** SWITCH GATE — see SWITCH-1.md once written ***

## Phase 2 — Model roster benchmark
Not started. `modules/home-manager/apps/goose-bench.nix` (lean v1) already exists from 2026-09-16.
Models to test are already pulled (saves significant time). Plan: extend the harness in place,
run in background while later phases proceed (each cell is a real LLM invocation, this is slow).

## Phase 3-9
Not started yet. See TaskList (TaskCreate #3-#9) for the live checklist — kept in sync with this
file's section headers.

## Environment notes for future-me
- `hyprctl` needs clean env (`env -i ...`) from this Bash tool — see Phase 0.
- Quickshell live PID: check `pgrep -af quickshell` before any QML work; never edit
  `quickshell/modules/**` files that are actually imported by `shell.qml` without staging first.
- Disk: 69GB free at session start on `/`. Recheck before any further `ollama pull`.
