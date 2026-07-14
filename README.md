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

**Caution:** don't physically unplug the eGPU while it's live. Surprise
removal makes amdgpu's teardown path time out (`ring kiq test failed`,
`failed to halt cp gfx`), which wedges the Hyprland compositor into a full
black screen (audio keeps working) that only a reboot clears. Deauthorize
it first via `/sys/bus/thunderbolt/devices/<id>/authorized` (write `0`)
before disconnecting.

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
