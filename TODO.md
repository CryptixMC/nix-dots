# TODO / Roadmap

Living roadmap for the Quickshell desktop (bar, launcher, greeter, theme system) and its remaining app-theming/ecosystem threads. Tree first for a 30-second scan, details below. `[x]` = shipped, `[~]` = designed but not built, `[ ]` = open thread.

## Tree

- **Shell & Theme System**
  - [x] Folder-based theme registry — `ultraviolet` + `catppuccin`, runtime-discovered ([§1](#1-theme-system))
  - [x] Wallpaper engine — static / gif / shader, per-theme, fullscreen-pause
  - [x] Live-sync: Hyprland borders, Ghostty colors, Zed chrome
  - [ ] Zen browser theming — real preset found, not wired ([§1](#1-theme-system))
  - [ ] Claude Desktop theming — hard limitation, documented not chased
  - [~] Runtime theme-switcher UI — becomes the Launcher's Themes tab ([§3](#3-launcher-tabs))
- **Bar**
  - [x] Waybar + Walker fully retired, Quickshell is the only shell
  - [x] Swappable per-icon popup (`BarIcon.popupComponent`)
- **Launcher** ([§3](#3-launcher-tabs))
  - [x] Tab bar — Applications / Games / Files / Themes
  - [~] Games tab content
  - [~] Files tab content
  - [~] Themes tab content
- **Greeter** ([§4](#4-greeter))
  - [x] Quickshell greeter replacing ReGreet (password-only v1)
  - [x] Status icons — battery / brightness / volume / bluetooth
  - [x] Animated wallpaper
  - [x] Fingerprint prompt text shortened
  - [~] Lock screen — designed, not built ([§5](#5-lock-screen-designed-not-built))
- **Fingerprint / PAM** — architectural ceiling, prior art, security note ([§2](#2-fingerprint--pam))
- **Reference** — Omarchy, other Quickshell shells worth reading ([§6](#6-reference-repos))

---

## 1. Theme system

Everything pulls from `themes/<name>/{base16.yaml, theme.json?, wallpapers/, components/?}`. `base16.yaml` is mandatory and feeds both Stylix (build-time) and Quickshell (runtime, via `yq`). `theme.json` and `components/` are optional — a colors-only theme is valid (`ultraviolet` ships neither).

**Live-synced today** (no rebuild needed, flips the instant `ThemeState.setTheme()`/`cycleTheme()` runs):
- Hyprland active/inactive border colors (`hyprctl eval` + `hl.config(...)`, since this repo's Lua config backend doesn't support `hyprctl keyword`)
- Ghostty terminal colors, via a `config-file` include Ghostty always loads after its own `theme = stylix` baseline
- Zed **chrome only** (background/borders/tabs/panels/terminal ANSI) — written to `~/.config/zed/themes/quickshell-live.json` using Stylix's own generated `stylix.json` as the 141-key structural template. Syntax-highlighting colors and player-cursor colors deliberately stay static (whatever Stylix last generated for `ultraviolet`) — full syntax remapping is a lot of extra surface for a cosmetic win where the editor buffer itself is a small fraction of the screen most of the time.

**Zed's build-time half**: `zed.nix` sets `theme = lib.mkForce "Quickshell Live"`, overriding Stylix's own `theme = "Base16 <name>"` default. Needs `nh home switch` once to take effect (untested this pass whether an already-open Zed window hot-reloads the *content* of a custom theme file it already has selected — Zed's settings.json hot-reload is well-established, but a referenced theme file's content re-reading on change is a separate, unconfirmed mechanism).

**Zen browser — real option found, not wired up**: the `zen-browser-flake` input bundles home-manager modules (`hm-module/presets/catppuccin.nix`) with a genuine `programs.zen-browser.profiles.<name>.presets.catppuccin.enable` option using the real `catppuccin/zen-browser` userChrome theme (flavor/accent configurable) — not just GTK inheritance. Not wired up yet because `zen-browser.nix` currently declares **no** home-manager-managed profile at all; the browser is running on a profile it created itself (`~/.config/zen/huedeu9v.Default Profile`). Turning on the preset means first deciding how to bring that live profile under home-manager's management (name it explicitly, or accept a second profile appearing) — a decision for whoever's driving, not something to guess at from here. Baseline GTK dark-mode (`gsettings ... prefer-dark`, already set in `hyprland.nix`'s autostart) covers native dialogs regardless.

**Claude Desktop**: Electron, no settings hook, no Stylix target. Only lever is GTK dialog chrome inheriting the system dark theme (already happening). Content-level theming isn't achievable from the Nix side — documented limitation, not a bug to keep chasing.

---

## 2. Fingerprint / PAM

- [x] Shortened fprintd timeout for `sudo`/TTY `login` (`modules/nixos/services/fprintd.nix`: `timeout = 5; max-tries = 2`). Explicitly disabled for `sshd` and `greetd`.
- **Architectural ceiling**: PAM's conversation model is sequential for a plain terminal — whichever module runs first blocks until success/timeout. No stock "race both, take whichever's ready."
- **Real prior art for a proper fix**: [Fingwit](https://github.com/xapp-project/fingwit)'s `pam_fingwit.so` — decides at runtime whether a scan is likely to succeed, skips straight to password if not, instead of blocking on a doomed read.
  - [ ] Evaluate swapping in `pam_fingwit.so` in place of the flat timeout.
- **Security note**: [CVE-2024-37408](https://linuxsecurity.com/news/security-projects/fingwit-biometric-authentication) — fingerprint-only auth on `su`/`sudo`/`polkit` can let a background process obtain privileges without a real scan prompt. Read before making fingerprint more automatic/prominent anywhere.
- The greeter's PAM conversation (via `Quickshell.Services.Greetd`) is genuinely sequential too — real concurrent fingerprint+password at the greeter isn't achievable without driving the PAM conversation directly (`Quickshell.Services.Pam`), which is architecturally a lock-screen-shaped project (see §5), not a greeter tweak.

---

## 3. Launcher tabs

`LauncherState.tabs` is a plain data list (`{id, label, glyph}`) — adding a fifth tab later is one entry, not a new code path. The tab row itself (pill-shaped, icon-only, hover/active-expands to icon+label) is built and live; only "Applications" has real content behind it so far.

### Games tab (designed, not built)
- Horizontally-scrollable "recommended" row up top.
- Below it, vertically-stacked sections: one multi-row grid of the full library, then one section per launcher (Steam, Prism Launcher, ...).
- Extensible per-launcher adapter model — adding a new launcher is "add a script," not "modify core logic."
- Search filters *within* each section (hides non-matches) rather than collapsing the section layout.

### Files tab (designed, not built — flagged for further iteration before building)
- Left: directory tree, defaulting to the home folder.
- Right: grid preview of the currently-open directory.
- Fuzzy search filters the tree/grid in place, and additionally surfaces a flat list of matching paths *outside* the current directory, underneath the tree.

### Themes tab (designed, not built)
- Top row: cycle installed themes (reuses `ThemeState`/`ThemeLoader` as-is).
- Second row: wallpapers available for the selected theme.
- Below: settings the *active theme* declares as configurable (e.g. light/dark toggle, font choice) — a theme that declares none shows no settings, same "colors-only theme is valid" principle as `theme.json` itself.

---

## 4. Greeter

`quickshell-greeter/` — separate Quickshell tree, runs as the unprivileged `greeter` user pre-login via `services.greetd` + `cage` (no wlr-layer-shell there, so it's a single `FloatingWindow`, not `PanelWindow`). Deliberately decoupled from the daily-driver shell's theme registry (`quickshell-greeter/theme/Colors.qml` is its own hand-picked palette) — an in-progress edit to the desktop shell should never risk the login screen.

- [x] Password-only auth flow via `Quickshell.Services.Greetd`, session/user fixed (not enumerated at runtime).
- [x] Status icons — `modules/status/{Battery,Brightness,Volume,Bluetooth}.qml`, trimmed adaptations of the bar's own modules, read-only (no click actions — nothing meaningful to change pre-login besides Wi-Fi, which already has its own picker).
- [x] Animated wallpaper — `modules/greeter/Wallpaper.qml`, static+gif only (no shader machinery, not worth the build complexity for a login screen), reusing `catppuccin`'s existing `retro2_live.gif` rather than sourcing anything new.
- [x] Fingerprint prompt shortened — `AuthState.onAuthMessage` substitutes "Scan fingerprint" for any message containing "finger", instead of relying on fprintd's exact (long) wording.
  - Worth a follow-up check: `fprintd.nix` sets `security.pam.services.greetd.fprintAuth = false`, so a fingerprint prompt reaching the greeter at all was a little surprising. Didn't block the text fix, but the "why" is still open.
- [ ] Brightness status icon's `/sys/class/backlight/.../brightness` read is unconfirmed under the `greeter` user's actual seat ACL — degrades to a harmless "0%" if it can't read, but not verified against a real seat-owning greeter session yet.

---

## 5. Lock screen (designed, not built)

Architecturally nothing like the greeter — greetd/cage only run **pre-login**. A lock screen has to run **inside the already-authenticated session**, using `Quickshell.Wayland`'s `WlSessionLock` / `WlSessionLockSurface` (`ext-session-lock-v1` — confirmed present in the installed Quickshell 0.3.1 qmltypes).

Reference implementation: **Omarchy**'s `shell/plugins/lock/Service.qml` (~620 lines) + `LockView.qml` (~220 lines) — a real, working `WlSessionLock`-based lock screen using `Quickshell.Services.Pam` (plus a parallel fingerprint flow). Worth carrying over:
- Stranded-lock recovery (a lock surface outliving its client after a shell restart)
- A stabilize-timer before actually engaging the lock (wait for outputs to be real)
- DPMS/idle reconciliation per monitor
- Animated/video background handling

Because this runs inside the live session (not pre-login), it can freely reuse the desktop's real theme registry, `Wallpaper.qml`, and bar-module patterns — no privilege-separation concern the way the greeter has. Trigger via `loginctl lock-session` / an idle-timeout policy; the "still maintains the desktop session, just saves battery" behavior layers on top via DPMS/suspend-adjacent settings once the lock surface itself works.

---

## 6. Reference repos

- **[Omarchy](https://github.com/omacom/omarchy)** (branch `quattro`) — real Quickshell-based shell with a genuine plugin architecture (`shell/plugins/*/manifest.json` + isolated QML). Coupling to Omarchy-specific behavior mostly shows up as external CLI calls rather than embedded logic, so most of it is reference/re-derive material rather than drop-in — the lock screen (§5) is the one piece confirmed directly adoptable near-verbatim. No tab-based launcher there (its menu is a hierarchical drill-down, not Spotlight-style tabs) — the launcher tab design (§3) is original.
- **[doannc2212/quickshell-config](https://github.com/doannc2212/quickshell-config)** — Ã  la carte reference bundling a status bar, launcher, notification daemon, and a runtime theme switcher with 206 bundled themes. Concrete prior art if the Themes tab (§3) grows a "browse community themes" feature later.
- **[SirAllap/quickshell-popups](https://github.com/SirAllap/quickshell-popups)** — theme-aware popup widgets including an existing `custom/claude-usage` module — prior art if a Claude-usage bar widget ever gets built.
- [Hyprland wiki: App Launchers](https://wiki.hypr.land/Useful-Utilities/App-Launchers/) / [Status Bars](https://wiki.hypr.land/Useful-Utilities/Status-Bars/) — general ecosystem, worth periodic re-checking.
