# nix-dots

cryptix's NixOS flake: one host (**carbon**, a ThinkPad T14 Gen 3 with an
AMD RX 6800 XT Thunderbolt eGPU), Hyprland, a fully custom
[Quickshell](https://quickshell.org) desktop, and Stylix theming.

- **Roadmap / open work:** [TODO.md](TODO.md)
- **Rules for coding agents:** [AGENTS.md](AGENTS.md)

---

## Layout

```
nix-dots/
├── flake.nix              # inputs and outputs: carbon system, home config, packages, checks
├── hosts/carbon/          # configuration.nix (system), home.nix (user), hardware-configuration.nix
├── modules/
│   ├── nixos/             # system: core/ hardware/ services/ apps/
│   ├── home-manager/      # user: core/ shell/ apps/ wm/
│   └── style/stylix.nix   # imported by both the system and the home config
├── desktop/
│   ├── shell/             # Quickshell desktop: bar, launcher, notifications, lock, wallpaper
│   ├── greeter/           # pre-login greeter (separate Quickshell tree, run by greetd)
│   └── themes/            # theme folders shared by Stylix and the shell
├── lib/                   # Nix helpers and the qubi boundary check
├── pkgs/                  # local derivations not in nixpkgs
├── .agents/skills/        # task guides for coding agents (see AGENTS.md)
├── AGENTS.md  README.md  TODO.md
└── .mcp.json              # MCP servers for coding agents
```

Nothing auto-discovers modules: a new one gets imported explicitly in
`hosts/carbon/configuration.nix` or `hosts/carbon/home.nix`.

---

## Usage

Home Manager is a **standalone** configuration, not a NixOS module, so the
system and the user environment switch separately:

```sh
nh os switch            # or: sudo nixos-rebuild switch --flake .#carbon
nh home switch          # or: home-manager switch --flake .#cryptix
```

Checking without switching:

```sh
nix flake check                          # evaluates both configs + the qubi boundary guard
nixos-rebuild build --flake .#carbon
nix build .#homeConfigurations.cryptix.activationPackage
nix build .#kitten-space-agency          # also: oneclient, oneclient-new-cluster, proton-drive-cli
nix fmt                                  # nixfmt-rfc-style
```

Flakes only see git-tracked files — `git add` new files (staging is enough)
before any Nix command. CI (`.github/workflows/check.yml`) runs the qubi
boundary check and `nixfmt --check` on every push.

---

## Desktop shell (Quickshell)

Quickshell is the only shell — Waybar, Walker, ReGreet and polkit-gnome
have all been replaced. Run it standalone with `quickshell -p desktop/shell`.

| Part | What it does |
|---|---|
| **Bar** (`modules/bar/`, flyouts in `bar/popups/`) | Workspaces, active window, media, clock/calendar, tray, CPU/RAM graphs, net speed, temperature, battery, backlight, volume/network/Bluetooth flyouts, quick settings, OSD |
| **Launcher** (`modules/launcher/`, one folder per tab) | Applications · `games/` (Steam + Prism) · `files/` (tree + grid file manager) · `system/` (about, install, themes, keybinds, monitor, display, services, maintenance, power, jobs) |
| **Notifications** (`modules/notifications/`) | Real notification daemon, toasts with action buttons and inline reply, notification centre with DND |
| **Polkit agent** (`modules/auth/`) | Quickshell holds the session's polkit slot and renders its own prompt |
| **Lock screen** (`modules/lock/`) | `WlSessionLock` + PAM (password or fingerprint) — built but not wired to a trigger yet, see [TODO §5](TODO.md#5-lock-screen) |
| **Wallpaper** (`modules/wallpaper/`) | Engines: `static`, `gif`, `shader`, `scene` (live QML scenes — Orbital, Neural — driven by real system stats) |
| **Greeter** (`desktop/greeter/`) | greetd + cage login screen, deliberately decoupled from the desktop shell's theme code |

Main keybinds (full list in `modules/home-manager/wm/hyprland.nix`, or the
launcher's System → Keybinds):

| Keys | Action |
|---|---|
| `SUPER+R` | Toggle the launcher |
| `SUPER+T` | Cycle the active theme live |
| `SUPER+D` / `SUPER+K` | Qubi chat overlay |
| `SUPER+G` | Steam in gamescope (evicts Ollama from VRAM around the session) |
| `SUPER+SHIFT+U` | Safely eject the eGPU — wait for "safe to unplug" |

---

## Themes

Each theme is a folder in `desktop/themes/<name>/`:

- `base16.yaml` — **required**; feeds Stylix at build time and Quickshell at runtime
- `theme.json` — optional token overrides (colors, radii, motion, wallpaper engine)
- `wallpapers/` — images, GIFs, shaders
- `components/` — optional per-theme QML overrides

| Theme | Notes |
|---|---|
| `ultraviolet` | Colors-only base theme; also Stylix's build-time scheme (`modules/style/stylix.nix`) |
| `ultraviolet-v2` | Same palette (its `base16.yaml` links to v1's) remapped to the Ultraviolet design system's Violet roles, Orbital scene wallpaper — see its [README](desktop/themes/ultraviolet-v2/README.md) |
| `catppuccin` | Catppuccin hand-mapped to this repo's base16 slot convention, shader wallpaper |

Switching themes at runtime (`SUPER+T` or launcher → System → Themes)
live-syncs the shell, Hyprland borders, Ghostty, and Zed's chrome with no
rebuild.

---

## Qubi

Qubi, the local-AI assistant, lives in its own repo
([CryptixMC/qubi](https://github.com/CryptixMC/qubi)) and comes in as the
`qubi` flake input. This repo only imports its modules and sets host values
(`services.qubi` in `hosts/carbon/configuration.nix`, `programs.qubi` in
`modules/home-manager/apps/qubi.nix`). The `qubi-boundary-guard` flake check
fails if Qubi logic creeps into any `.nix`/`.qml` file outside the allowlist
in `lib/qubi-boundary-guard.nix`.

Qubi picks a model tier from `/run/ai-workstation/state.json` (`docked` /
`undocked` / `gaming`). The eGPU hotplug scripts in `amd.nix` update it on
dock/undock through Qubi's own attach/release units;
`modules/nixos/apps/ai-workstation.nix` sets it at boot and around gaming.

---

## Hardware notes (carbon)

The full detail lives in comments next to each fix and in
`.agents/skills/egpu-dock-undock/SKILL.md`.

- **eGPU hard hangs under load** — PCIe AER fatal errors on the Thunderbolt
  tunnel wedged the system. Fixed with `pci=noaer` in
  `modules/nixos/hardware/amd.nix`.
- **Unplugging the eGPU** — surprise removal can black-screen Hyprland.
  Press `SUPER+SHIFT+U` first: it stops Ollama/kanshi, drops the eGPU
  outputs, unbinds amdgpu while the link is live, then deauthorizes the
  tunnel. `egpu-eject.service` has a best-effort udev backstop, but it
  isn't guaranteed. If it wedges anyway: SSH in over Tailscale and
  `sudo systemctl restart display-manager.service` or reboot.
- **Reboot after any crashed removal** — it can leave ROCm/KFD compute dead
  (`rocminfo` shows no GPU agents) even though the display side looks fine,
  and an orphaned `llama-server` stuck in `D` state.
- **ROCm "out of memory" after an aborted model load** is fragmented VRAM,
  not a BAR limit — `sudo systemctl restart ollama.service` and retry.
- **Dock topology** — plug the USB-C dock into the laptop's second TB4
  port, not the eGPU enclosure's passthrough (which shares bandwidth with
  the GPU tunnel).
- **CPU power-limit throttling** — the BIOS ships PL1 = 64W forever.
  `throttled.service` (`modules/nixos/hardware/thinkpad-power.nix`) sets
  PL1 35W / PL2 54W on AC; CPU governor and GPU DPM go to performance only
  while the eGPU is docked.

---

## Coding agents

Everything agent-related is tool-neutral, with thin pointers for tools that
insist on their own filenames:

- `AGENTS.md` — the rules, read natively by most agents; `.claude/CLAUDE.md` just imports it
- `.agents/skills/` — task guides (`nix-dots-conventions`, `egpu-dock-undock`, `game-log-discovery`); `.claude/skills` links here
- `.mcp.json` — MCP servers by command name; `modules/home-manager/apps/agents.nix` puts them on PATH

---

## Credits

[NixOS](https://nixos.org/) · [Home Manager](https://github.com/nix-community/home-manager) ·
[Stylix](https://github.com/danth/stylix) · [Base16](https://github.com/chriskempson/base16) ·
[Hyprland](https://hyprland.org/) · [Quickshell](https://quickshell.org/)
