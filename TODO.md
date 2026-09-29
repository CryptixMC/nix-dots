# TODO / Roadmap

Everything planned, in progress, or deliberately parked for this repo.
Open work comes first; the numbered sections below keep the design notes
and history behind each area (code comments link to them as `TODO.md §N`,
so keep the numbering stable).

`[ ]` open · `[~]` built, not yet verified live · `[x]` done

Qubi's own roadmap lives in [its repo](https://github.com/CryptixMC/qubi).

---

## Open work

### Theming ([§1](#1-theme-system))
- [ ] Get every remaining app styled via Stylix (or the live-sync path)
- [ ] Add a template/skeleton for new themes (`themes/<name>/` with `base16.yaml`, optional `theme.json`, `wallpapers/`)
- [ ] Zen browser theming — needs a decision on bringing the live profile under home-manager first
- Claude Desktop theming — not achievable from Nix; parked, not a bug

### Launcher ([§3](#3-launcher))
- [ ] System → Install sub-tabs still stubbed ("not built yet"): Generations, Modules, Dev Shells, Services, Fonts, Overlays
- [ ] Themes: a settings section once some `theme.json` actually declares options
- [ ] Games: more launchers (Lutris/Heroic) if they ever get installed

### Bar ([§6](#6-bar))
- [~] Network and Bluetooth flyouts — built and linted, never clicked on a real screen
- [ ] Bluetooth: pairing new devices from the flyout (needs a discovery trigger the API doesn't expose; `blueman-manager` covers it today)

### Fingerprint / PAM ([§2](#2-fingerprint--pam))
- [ ] Evaluate packaging `pam_fingwit` in place of the flat fprintd timeout (not in nixpkgs; security-sensitive, needs a deliberate hands-on session)
- [ ] Find out why a fingerprint prompt reached the greeter even though `greetd.fprintAuth = false`

### Lock screen ([§5](#5-lock-screen))
- [~] v1 built, unlock path never tested live
- [ ] Test the unlock path by hand (`quickshell ipc call lock lock`) with someone physically present
- [ ] Then wire a real trigger: keybind, idle timeout, `loginctl lock-session`
- [ ] Stranded-lock recovery, stabilize timer before engaging, per-monitor DPMS/idle handling
- [ ] Wallpaper-engine background instead of a flat color

### eGPU / AI workstation ([§7](#7-ai-workstation))
- [ ] Run `SUPER+G` end to end through a real Steam/gamescope session (VRAM eviction + post-game state are only unit-tested)
- [ ] Finish the Phase 1a checklist: docked (D3) compute control, undocked clean boot, D3 surprise-unplug, suspend/resume
- [ ] Verify the dock-topology fix empirically (`iperf3` over dock Ethernet during a GPU-bound game, before/after)
- [ ] Tune the `throttled` AC profile (PL1 35W / PL2 54W) using the package-throttle counter

### Flake housekeeping
- [ ] Point the `qubi` input back at `main` once the development branch merges (drop `?ref=…` in `flake.nix`)
- [ ] Switch `qubi` from `git+ssh` to `github:CryptixMC/qubi` once the repo is public
- [ ] Shrink the `qubi-boundary-guard` allowlist: remove the stale Qubi comments in `lib/scriptWithPath.nix`, `BarIcon.qml`, `QubiGlyph.qml`, then drop them from the list
- [ ] Retire the transitional allowlist entries (`qubi-hwstate.nix`, `claude-usage.nix`, `ai-workstation.nix`, `lib/mkUserScript.nix`) as Qubi takes over that logic

---

## 1. Theme system

Everything reads from `themes/<name>/{base16.yaml, theme.json?, wallpapers/, components/?}`.
`base16.yaml` is required and feeds both Stylix (build time) and Quickshell
(runtime, via `yq`). A colors-only theme is valid — `ultraviolet` ships
neither `theme.json` nor `components/`.

- [x] Folder-based theme registry, discovered at runtime (`ultraviolet`, `ultraviolet-v2`, `catppuccin`)
- [x] Wallpaper engines: static / gif / shader / scene, per theme, paused under fullscreen apps
- [x] Runtime switcher: launcher → System → Themes, plus a per-theme wallpaper picker (persisted per theme in `ThemeState.wallpaperOverrides`)

**Live-synced** the instant `ThemeState.setTheme()`/`cycleTheme()` runs:
- Hyprland active/inactive border colors (`hyprctl eval` + `hl.config(...)` — the Lua config backend doesn't support `hyprctl keyword`)
- Ghostty colors, via a `config-file` include loaded after its `theme = stylix` baseline
- Zed **chrome only** — written to `~/.config/zed/themes/quickshell-live.json` using Stylix's generated `stylix.json` as the template; `zed.nix` forces `theme = "Quickshell Live"`. Syntax colors stay at whatever Stylix last generated — a lot of surface for a small cosmetic win.

**Zen browser**: `programs.zen-browser.profiles.<name>.presets.catppuccin` is a
real option, but the module asserts "exactly one default profile" as soon as
any profile is declared and doesn't know about the existing self-managed
profile. `isDefault = false` fails to evaluate; `isDefault = true` risks
changing which profile launches. Needs a migration decision first. GTK
dark mode already covers native dialogs.

**Claude Desktop**: Electron, no settings hook, no Stylix target. Only GTK
dialog chrome follows the system theme.

---

## 2. Fingerprint / PAM

- [x] Short fprintd timeout for `sudo`/TTY `login` (`fprintd.nix`: `timeout = 5`, `max-tries = 2`); disabled for `sshd` and `greetd`.
- **Ceiling**: PAM's conversation is sequential — whichever module runs first blocks until success or timeout. No stock "race both".
- **Prior art**: [Fingwit](https://github.com/xapp-project/fingwit)'s `pam_fingwit.so` decides up front whether a scan is likely and skips straight to password if not. Not packaged in nixpkgs.
- **Security note**: [CVE-2024-37408](https://linuxsecurity.com/news/security-projects/fingwit-biometric-authentication) — fingerprint-only auth on `su`/`sudo`/`polkit` can let a background process gain privileges without a real prompt. Read before making fingerprint more automatic anywhere.
- The greeter's `Quickshell.Services.Greetd` conversation is sequential too; true concurrent fingerprint+password needs `Quickshell.Services.Pam` directly (the lock screen's approach, §5).

---

## 3. Launcher

`LauncherState.tabs` is a plain data list (`{id, label, glyph}`) — a new tab
is one entry. Tabs are pill-shaped (icon-only, expand to icon+label on
hover/active) and every non-Applications tab loads lazily, so the Games and
Files filesystem scans never run until that tab opens.

- [x] **Applications** — `ThemedIcon` tints app icons toward the theme accent
- [x] **Games** — Steam (`appmanifest_*.acf`) and Prism Launcher (`instance.cfg`) libraries with cover art, discovered in a few batched `grep`/`find` calls. Recently-played row, full grid, per-launcher grids. A new launcher is one more `Process` block in `GamesLibrary.qml`.
- [x] **Files** — real file manager: expand/collapse tree (`FilesTree.qml`), fuzzy-filtered grid with cross-directory "Elsewhere" results (`FilesPane.qml`), breadcrumb, context menu, rename/new/confirm prompts.
- [x] **System** — left-nav sections: About, Install (Packages / Installed / Flatpak / Pending), Themes, Keybinds, Monitor, Display, Services, Maintenance (generations, disk usage, GC), Power, Jobs.

Lessons worth keeping:
- `Image.source` needs a bare filesystem path, not a constructed `file://` URL, for names with spaces or brackets.
- **Loader sizing**: an explicit `height` on a `Loader` force-resizes its item (feedback loop, height froze at 0); making `implicitHeight` depend on `height` is a binding loop; inactive Loaders don't reliably report 0 height, so each per-tab `Loader` uses `visible: active` so the `Column` ignores it. Tabs now compute a fixed `computedHeight` and scroll internally.
- `adwaita-icon-theme` has to be installed explicitly — without it every named-icon lookup silently fell back to blank icons.

---

## 4. Greeter

`quickshell-greeter/` — a separate Quickshell tree run as the unprivileged
`greeter` user by `services.greetd` + `cage` (no layer-shell there, so a
single `FloatingWindow`). Its palette (`theme/Colors.qml`) is hand-picked
rather than imported from the desktop shell, so an in-progress shell edit
can never break the login screen; visual drift is the accepted tradeoff.

- [x] Password auth via `Quickshell.Services.Greetd`, fixed user/session
- [x] Read-only status icons: battery, brightness, volume, Bluetooth, plus a Wi-Fi picker
- [x] Animated wallpaper (static + gif only)
- [x] Fingerprint prompt shortened to "Scan fingerprint"
- [x] Brightness read is safe as `greeter` (`/sys/class/backlight/*/brightness` is world-readable)
- Rollback to ReGreet: see the comment at the top of `modules/nixos/services/greetd.nix`

---

## 5. Lock screen

Runs **inside** the authenticated session via `Quickshell.Wayland`'s
`WlSessionLock` (`ext-session-lock-v1`), unlike the pre-login greeter.

- `quickshell/modules/lock/{LockService,LockView}.qml` + `modules/nixos/services/quickshell-lock.nix`.
- `LockService` drives `Quickshell.Services.Pam`'s `PamContext` against a bare `security.pam.services.quickshell-lock = {}` — confirmed to build a complete fprintd-then-password stack from the global `fprintAuth` default.
- `LockView` shows a clock, prompt/error text and a password field on a flat themed background. No Escape-to-dismiss.
- **Shipped inert on purpose**: the only trigger is `quickshell ipc call lock lock` (and the launcher's Power section, labeled as untested). A broken unlock path means being locked out, so it stays unwired until tested live once.
- Open question to confirm on the first live test: whether `pam.start()` can be called again directly after a failed attempt (type signatures suggest yes).
- Omarchy's lock screen (`shell/plugins/lock/`) is the reference for the missing robustness pieces listed under Open work.

---

## 6. Bar

- [x] Waybar and Walker fully retired
- [x] Per-icon popups via `BarIcon.popupComponent`; volume, network, Bluetooth, media and calendar flyouts, quick settings panel, OSD
- [x] Real notification daemon: toasts with action buttons and inline reply, notification centre with history + DND (`modules/notifications/`)
- [x] Quickshell polkit agent replaces polkit-gnome (`modules/auth/`)

**Network flyout** (`NetworkPopup.qml`): Wi-Fi networks by signal strength,
live scan while open, one-click connect for known/open networks, inline
password field for new secured ones, `nmtui` link for everything else
(hidden SSIDs, enterprise auth).

**Bluetooth flyout** (`BluetoothPopup.qml`): known devices with
connect/disconnect and battery level. No pairing — `BluetoothAdapter` has
no discovery trigger in this API — so `blueman-manager` is the escape hatch.

---

## 7. AI workstation

The laptop's eGPU state drives Qubi's model routing. What lives here is the
host-specific part: the eGPU/Thunderbolt hardening (`amd.nix`) and the
state-file bridge (`ai-workstation.nix`). Everything downstream of the state
file is Qubi's concern — see its
[development log](https://github.com/CryptixMC/qubi/blob/main/docs/development-log.md).

### Phase 1a — eGPU hotplug hardening
- [x] Kernel pinned (`linuxPackages_6_18`) so a flake update can't silently move it out from under the Thunderbolt/amdgpu workarounds
- [x] `egpu-eject` refuses to eject while `gamescope` is running
- [x] Headless ROCm compute verified on the eGPU (`ollama ps` → 100% GPU); a surprise unplug in that state did not hang Hyprland
- [ ] Docked compute control, undocked clean boot, docked surprise-unplug, suspend/resume

**Known failure mode**: after a crashed or surprise removal, udev backstops
may not re-fire, and ROCm/KFD compute can be dead (`rocminfo` shows zero
GPU agents) while `amdgpu` looks cleanly bound. A model loaded at that
moment leaves an unkillable `llama-server`. **Reboot after any crashed
removal.** `qubi-health` reports this state read-only.

### Phase 1b — state bridge into Qubi
- [x] `/run/ai-workstation/state.json` (tmpfs), `ai-workstation-{dock,undock}-sync` oneshots with scoped NOPASSWD sudo rules
- [x] Hooked into `egpu-bar-fix`/`egpu-eject` and the `SUPER+G` gaming keybind
- [x] Verified end to end on real hardware for dock and undock
- [ ] Full `SUPER+G` launch → play → exit cycle

---

## 8. Reference repos

- **[Omarchy](https://github.com/omacom/omarchy)** (branch `quattro`) — Quickshell shell with a real plugin architecture; its lock screen is the most directly reusable piece.
- **[doannc2212/quickshell-config](https://github.com/doannc2212/quickshell-config)** — bar, launcher, notifications and a runtime theme switcher with 206 bundled themes; prior art for a "browse community themes" feature.
- **[SirAllap/quickshell-popups](https://github.com/SirAllap/quickshell-popups)** — theme-aware popups including a `custom/claude-usage` module.
- Hyprland wiki: [App Launchers](https://wiki.hypr.land/Useful-Utilities/App-Launchers/) · [Status Bars](https://wiki.hypr.land/Useful-Utilities/Status-Bars/)
