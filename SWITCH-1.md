# SWITCH GATE 1 — Phase 1 (rebrand + system modules) ready to activate

Everything below is committed on branch `qubi/overnight`, `nix flake check` clean,
`nixos-rebuild build --flake .#carbon` clean, home-manager activation package builds clean,
`qml-lint-repo` clean (same baseline as before tonight — no new warnings introduced).

## What this switch activates
- zram swap (50%, zstd) — no swap exists today, this is real OOM protection.
- `qubi-health` advisory timer + CLI (`qubi-health` on PATH after `nh home switch`... actually
  this one's a NixOS `environment.systemPackages` entry, so it needs `nh os switch` specifically).
- `ai-workstation-suspend-evict` sleep hook (evicts loaded Ollama models before suspend).
- Reserved keybinds SUPER+U/I/O/N/SHIFT+D (all currently no-op gracefully — nothing to break).
- Qubi rebrand: `qubi-code`/`qubi-claude`/`qubi-plan`/`qubi-chat`/`qubi-state-sync`/`qubi-bridge`
  on PATH, with `goose-*` aliases kept for muscle memory.
- `qubi-bridge` + `qubi-mobile-static` systemd **user** services (mobile GUI over Tailscale) —
  these need `nh home switch` specifically, not `nh os switch`.

## Commands to run, in order

```
cd ~/nix-dots
nh os switch    # NixOS-level: zram, qubi-health, amdgpu params (already live), sudo rules
nh home switch  # home-manager: qubi-* wrappers, qubi-bridge/qubi-mobile-static services, hyprland keybinds
```

Both are non-destructive rebuilds of an already-`build`-verified config — the derivations above
were already realized during this session's verification pass, so the switch itself should be
fast (mostly activation scripts, not new builds).

## After switching, quick sanity checks (safe, read-only)
```
qubi-health                                  # should print HEALTHY/EGPU-ABSENT/etc, not an error
systemctl status qubi-health.timer           # should be active/waiting
systemctl --user status qubi-bridge qubi-mobile-static   # should both be active/running
qubi-code --help 2>&1 | head -1              # sanity that the wrapper resolves
```

## Why this doesn't need to happen before I keep working
None of Phase 2 onward requires this switch: model benchmarking uses the CLI tools already on
PATH from the current generation; QML module development happens in `~/qubi-staging/` outside
the repo per the safety protocol, and only gets registered in `shell.qml` (itself gated behind
its own staging validation, independent of this switch) at the very end of each module's work.
I'm continuing straight into Phase 2 without waiting for you to run this.
