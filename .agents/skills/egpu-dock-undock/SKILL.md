---
name: egpu-dock-undock
description: How this laptop's AMD RX 6800 XT eGPU hotplug system works, its known failure modes, and how to check its state safely. Load before touching anything eGPU/ROCm/Ollama-routing related.
---

# eGPU dock/undock state machine and failure modes

## Hardware and detection
AMD RX 6800 XT over Thunderbolt, PCI id `1002:73bf`. `lspci -d 1002:73bf`
is the ground-truth presence check. `modules/nixos/hardware/amd.nix` owns
udev rules keyed on that vendor/device id:
- **Dock** (cable plugged in) → `egpu-bar-fix.service` fires.
- **Undock** (cable removed) → `egpu-eject.service` fires, safely
  unbinding the driver.
- `egpu-eject.service` refuses to eject (notifies instead) if `gamescope`
  is running — a live game's own DRM context could hang the unbind the
  same way ROCm's can.

## The AI-routing layer on top
`modules/nixos/apps/ai-workstation.nix` writes `/run/ai-workstation/state.json`
(tmpfs, `{state, provider, model, updated}`) on every dock/undock event
(triggered from `egpu-bar-fix`/`egpu-eject`'s own success branch, not a
second udev rule) and at boot (`ai-workstation-boot-sync.service`, since a
boot with no hotplug event never re-fires the trigger). `state` is one of
`docked`/`undocked`/`gaming` — `gaming` sets `model: null` deliberately
(SUPER+G's gaming-start script), signaling "no local model routing, keep
the GPU free for the game." `qubi-engine` (from the qubi flake input)
watches this file and handles model selection itself; `qubi-state-sync`
(`modules/home-manager/apps/qubi-hwstate.nix`) only sends the desktop
notification.

## The dead-KFD failure mode — read this before assuming "eGPU is fine"
A crash or bad disconnect can leave `amdgpu` cleanly bound with a valid
PCI BAR (looks fine at the driver/display level) while ROCm/KFD compute
is **silently dead underneath** — `rocminfo` reports zero GPU agents
despite the card showing up fine in `lspci`. This has now happened on
this machine on **multiple separate occasions**, most recently live
during a benchmark run on 2026-09-18.
Symptoms once in this state:
- `rocminfo | grep "Device Type:.*GPU"` → zero matches, while
  `lspci -d 1002:73bf` still shows the card.
- Any Ollama request against the dead GPU hard-hangs (confirmed: a
  `curl .../api/generate` call timed out completely, no response, no
  error).
- `ollama ps` and `systemctl status ollama.service` **both hang** trying
  to enumerate the process tree, because of an orphaned `llama-server`
  child stuck in genuine `D` (uninterruptible sleep) state — unkillable,
  survives `systemctl restart`/`stop` of `ollama.service` itself.
- `ollama.service` keeps serving requests that don't touch the wedged
  runner fine in the meantime — it's specifically anything that needs to
  enumerate/stop the wedged process that hangs.

**The only known fix is a full reboot.** Nothing in this codebase
attempts to fix this automatically — the health-check timer is
deliberately advisory-only, on purpose (see below).

## Checking state safely
Use `qubi-health` (CLI + `qubi-health.timer`, every 5 min,
now provided by the qubi flake's NixOS module) — prints one of `HEALTHY` /
`DEAD-KFD-REBOOT-REQUIRED` / `WEDGED-RUNNER` / `EGPU-ABSENT`. It is
read-only by design: it must never kill, restart, or otherwise act on
what it finds, since the only real fix (reboot) isn't something any
script should do unattended. Run this — not `ollama ps` — as the first
check before trusting any AI feature that needs the docked GPU; `ollama
ps` itself can be one of the things that's hanging.

## Suspend/resume
`ai-workstation-suspend-evict` (bound to `sleep.target`) runs `ollama
stop` on every currently-loaded model before suspend — a model still
"loaded" against hardware that's about to go through a full power-state
transition is the same shape of risk as a surprise eGPU removal.
Always-exits-0 by design so it can never hang or block suspend itself.
