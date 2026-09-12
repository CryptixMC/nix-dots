# cryptix's NixOS Dotfiles

Welcome to my NixOS configuration! This repository is designed for modularity, theming, and reproducibility across multiple machines. It leverages Nix flakes, Stylix for unified theming, and Home Manager for user-level configuration.

---

## TO-DO
- [ ] get all modules to be styled via stylix
- [ ] add a template for styles
- [ ] waybar is a WIP

---

## Known Hardware Issues

**carbon (ThinkPad T14 Gen3) — AMD RX 6800 XT eGPU over Thunderbolt**

The eGPU (Adaptertek Tamales2, TB3/Titan Ridge) tunneled through the laptop's
native TB4 controller was hard-hanging under sustained gaming load: a PCIe
AER correctable-error flood would escalate and eventually hit an
Uncorrectable (Fatal) error, which Linux's AER recovery can't handle for
Thunderbolt-tunneled devices (no `error_detected` driver callback), wedging
into a `hung_task` and a full system hang. Fixed by adding `pci=noaer` to
`boot.kernelParams` in `modules/nixos/hardware/amd.nix` — see the comment
there for the full root-cause writeup.

**Unplugging the eGPU:** surprise removal makes amdgpu's teardown path time
out (`ring kiq test failed`, `failed to halt cp gfx`), which wedges the
Hyprland compositor into a full black screen (audio keeps working) that
only a reboot clears — because amdgpu tries to talk to hardware that just
electrically vanished mid-teardown. Press **SUPER+SHIFT+U** first: it stops
ollama/kanshi, tells Hyprland to drop the eGPU-attached outputs, unbinds
amdgpu while the link is still live (so its teardown completes against
responsive hardware), then deauthorizes the Thunderbolt tunnel. Wait for
the "safe to unplug" notification before pulling the cable. There's also a
best-effort automatic udev rule for when you forget and yank it anyway
(`egpu-eject.service` in `modules/nixos/hardware/amd.nix`), but it's racing
the same hang and isn't guaranteed to win.

If it wedges anyway: SSH in over Tailscale, check
`journalctl -k -b --since "-2 min"` for the failure, then
`sudo systemctl restart display-manager.service` (gets a fresh Hyprland
session without a full reboot) or, failing that, a graceful `sudo reboot`.

**Ollama/ROCm: "cudaMalloc failed: out of memory" on a large model after an
aborted load.** If a model load is interrupted (e.g. the client gives up
waiting mid-load), amdgpu can be left with fragmented/leaked VRAM that
causes the *next* load attempt to fail with a ROCm OOM — even for a model
that fit fine before. This is **not** a PCIe BAR/VRAM-aperture limit: the
GPU's BAR 0 is fixed at 256MB by `egpu-bar-fix.service` (see above), but
ROCm can still place full-size allocations well beyond that in "invisible"
VRAM — confirmed live by loading a 36B model (~16GB) to completion on a
freshly restarted `ollama.service`, with no BAR/kernel changes needed. If
you hit this OOM, `sudo systemctl restart ollama.service` and retry before
assuming a hardware ceiling.

**Dock topology — don't daisy-chain the USB-C dock through the eGPU
enclosure.** The laptop has two independent, CPU-integrated Thunderbolt 4
controllers (confirmed via `lspci -tv`: separate root ports, separate
NHIs) — not bandwidth-shared. But the ThinkPad USB-C Dock Gen 2's upstream
cable was found plugged into the eGPU enclosure's own USB-C passthrough
port instead of the laptop's second, idle TB4 port — daisy-chaining it
through the enclosure's internal Titan Ridge chip, which *does* share
bandwidth across its two ports (unlike the laptop's own two ports), so the
dock's USB/Ethernet/audio traffic was contending with the GPU's own PCIe
tunnel on the same cable. Fix: plug the dock directly into the laptop's
second TB4 port. Verify empirically after moving it — run `iperf3`/a large
file transfer over the dock's Ethernet concurrently with a GPU-bound game
session and compare fps/frametime and throughput against a baseline from
before the move, since this hasn't been confirmed against an authoritative
Intel doc.

**CPU package power limit (PROCHOT) throttling under sustained gaming
load.** This T14 Gen 3's BIOS ships an unmanaged PL1 = 64W with an
effectively meaningless 127.9s time window — i.e. sustained 64W forever —
instead of the i7-1260P's stock 28W. Confirmed via
`thermal_throttle/package_throttle_count` climbing continuously during
play sessions (thousands of events, tens of seconds of cumulative
throttling) and package temp still reading 74°C six minutes after a game
exited. This starves the eGPU of submitted work — it was observed at 72%
busy but drawing only 52W of its 272W cap, the signature of a GPU waiting
on the CPU rather than being GPU-bound. Fixed system-wide (AC/battery-
aware, not eGPU-gated, since it's a firmware bug rather than a
gaming-specific tradeoff) by `throttled.service` in
`modules/nixos/hardware/thinkpad-power.nix`, starting at a conservative
PL1=35W/PL2=54W AC profile — tune via the same throttle-counter method
used to diagnose this if it needs adjusting. Separately, CPU governor and
GPU DPM are forced to performance/high only while the eGPU is docked
(`egpu-perf-on`/`egpu-perf-off` in `modules/nixos/hardware/amd.nix`,
piggybacking on the existing `egpu-bar-fix`/`egpu-eject` triggers).

---

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Theming with Stylix](#theming-with-stylix)
- [Hosts](#hosts)
- [Modules](#modules)
- [Home Manager](#home-manager)
- [How to Use](#how-to-use)
- [Screenshots](#screenshots)
- [Credits](#credits)

---

## Overview

This repo uses Nix flakes for reproducible system and user configurations. Key features include:

- **Stylix** for unified, system-wide theming
- Modular NixOS and Home Manager configs
- Custom themes (see `themes/ultraviolet`)
- Support for multiple hosts

---

## Directory Structure

```
nix-dots/
├── assets/         # Extra theme assets (e.g., for editors)
├── files/          # (Currently empty, for future use)
├── hosts/          # Host-specific configs
├── modules/        # Modular NixOS & Home Manager configs
├── old-stuff/      # Legacy configs
├── themes/         # Custom themes (e.g., Ultraviolet)
├── flake.nix       # Flake entry point
├── flake.lock      # Flake lock file
└── README.md       # This file
```

---

## Theming with Stylix

Stylix is configured system-wide (not via Home Manager) for consistent theming.
The main theme is **Ultraviolet**, defined in `themes/ultraviolet/`.

- **Wallpaper:** `themes/ultraviolet/alyssa.png`
- **Color scheme:** `themes/ultraviolet/ultraviolet.yaml`
- **Polarity:** `themes/ultraviolet/polarity.txt` (`dark`)
- **Base16 colors:** `themes/ultraviolet/colors.yaml`

Stylix is imported in `modules/nixos/style/stylix.nix` and enabled in each host config.

_Screenshot: Stylix theme in action_
![Stylix screenshot](screenshots/stylix-theme.png)

---

## Hosts

Each machine has its own config in `hosts/`.
Example: `hosts/carbon/` contains:

- `configuration.nix` (system config)
- `hardware-configuration.nix` (hardware details)
- `home.nix` (user config)

_Screenshot: Host-specific desktop_
![Host screenshot](screenshots/host-carbon.png)

---

## Modules

Reusable modules are in `modules/`:

- `modules/nixos/` for system modules (apps, hardware, style, window managers)
- `modules/home-manager/` for user-level modules

_Screenshot: Modular config structure_
![Modules screenshot](screenshots/modules-structure.png)

---

## Home Manager

User configuration is managed via Home Manager, integrated with flakes.
See `hosts/carbon/home.nix` and `modules/home-manager/`.

_Screenshot: Home Manager apps and settings_
![Home Manager screenshot](screenshots/home-manager.png)

---

## How to Use

1. **Clone the repo:**
   ```sh
   git clone https://github.com/CryptixMC/nix-dots.git
   cd nix-dots
   ```

2. **Build your system:**
   ```sh
   sudo nixos-rebuild switch --flake .#carbon
   ```

3. **Customize themes:**
   - Edit files in `themes/ultraviolet/`
   - Update `modules/nixos/style/stylix.nix` as needed

---

## Screenshots

Add screenshots of your desktop, terminal, apps, etc. here for visual reference.

- Stylix theme: ![Stylix screenshot](screenshots/stylix-theme.png)
- Host desktop: ![Host screenshot](screenshots/host-carbon.png)
- Modules structure: ![Modules screenshot](screenshots/modules-structure.png)
- Home Manager: ![Home Manager screenshot](screenshots/home-manager.png)

---

## Credits

- [Stylix](https://github.com/danth/stylix)
- [Base16](https://github.com/chriskempson/base16)
- [NixOS](https://nixos.org/)
- [Home Manager](https://github.com/nix-community/home-manager)

---
