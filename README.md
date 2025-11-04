# cryptix's NixOS Dotfiles

Welcome to my NixOS configuration! This repository is designed for modularity, theming, and reproducibility across multiple machines. It leverages Nix flakes, Stylix for unified theming, and Home Manager for user-level configuration.

---

## TO-DO

### Theming
- [ ] Make themes easier to configure and switch, potentially using `walker`.
- [ ] When switching themes, also update the Waybar configuration.
- [ ] Get all modules to be styled via stylix.
- [ ] Add a template for styles.

### Waybar
- [ ] Complete the Waybar configuration.
- [ ] Integrate Waybar with theme switching.

### Hyprland
- [ ] Fine-tune Hyprland configuration.

### File Browser
- [ ] Choose and configure a file browser.

### Walker (rofi replacement)
- [ ] Implement `walker` as the main application launcher and window switcher.
- [ ] Configure `walker` for theme switching.
- [ ] Implement `walker` as a file searcher.
- [ ] Explore and implement other `walker` features like:
    - [ ] SSH launcher
    - [ ] Clipboard manager
    - [ ] Power management menu
    - [ ] Calculator

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
├── flake.lock
├── flake.nix
├── README.md
├── hosts/
│   └── carbon/
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       └── home.nix
├── modules/
│   ├── home-manager/
│   │   ├── apps/
│   │   ├── core/
│   │   ├── shell/
│   │   └── wm/
│   ├── nixos/
│   │   ├── apps/
│   │   ├── core/
│   │   ├── hardware/
│   │   ├── services/
│   │   └── wm/
│   └── style/
│       └── stylix.nix
└── themes/
    └── ultraviolet/
        ├── alyssa.png
        ├── background.png
        ├── backgroundsha256.txt
        ├── backgroundurl.txt
        ├── colors.yaml
        ├── polarity.txt
        └── ultraviolet.yaml
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

   > [!NOTE]
   > After the initial `nixos-rebuild switch`, you can use `nh` for faster rebuilds:
   > - `nh os switch .`: Rebuilds the NixOS configuration.
   > - `nh home switch .`: Rebuilds the Home Manager configuration.

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
