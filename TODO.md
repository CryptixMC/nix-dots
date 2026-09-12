# TODO / Roadmap

Living roadmap for the Quickshell desktop (bar, launcher, greeter, theme system) and its remaining app-theming/ecosystem threads. Tree first for a 30-second scan, details below. `[x]` = shipped, `[~]` = designed but not built, `[ ]` = open thread.

## Tree

- **Shell & Theme System**
  - [x] Folder-based theme registry — `ultraviolet` + `catppuccin`, runtime-discovered ([§1](#1-theme-system))
  - [x] Wallpaper engine — static / gif / shader, per-theme, fullscreen-pause
  - [x] Live-sync: Hyprland borders, Ghostty colors, Zed chrome
  - [ ] Zen browser theming — real preset found, not wired ([§1](#1-theme-system))
  - [ ] Claude Desktop theming — hard limitation, documented not chased
  - [x] Runtime theme-switcher UI — the Launcher's Themes tab ([§3](#3-launcher-tabs))
- **Bar**
  - [x] Waybar + Walker fully retired, Quickshell is the only shell
  - [x] Swappable per-icon popup (`BarIcon.popupComponent`)
- **Launcher** ([§3](#3-launcher-tabs))
  - [x] Tab bar — Applications / Games / Files / Themes
  - [x] Games tab — real Steam + Prism Launcher libraries
  - [x] Files tab — v1 tree/grid browser (flagged for a future redesign pass)
  - [x] Themes tab — cycle themes + per-theme wallpaper picker
  - [x] Icon/visual polish — `ThemedIcon` macOS-style tinting, themed glyph icons for files/folders, translucent card/icon backgrounds, real icon theme installed
  - [x] Tab-switch sizing bugs — whole-screen-height blowup, then 0-height collapse, then cross-tab height accumulation, all traced to `Loader` sizing semantics and fixed
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

`LauncherState.tabs` is a plain data list (`{id, label, glyph}`) — adding a fifth tab later is one entry, not a new code path. The tab row (pill-shaped, icon-only, hover/active-expands to icon+label) is built and live. The launcher box itself widens for Games/Files/Themes (960px vs. Applications' 564px) and each tab loads lazily (`Loader active: ...`) so Games/Files' background filesystem scans never run before that tab is opened.

### Games tab — built
- `GamesLibrary.qml` discovers real Steam (`appmanifest_*.acf`) and Prism Launcher (`instance.cfg`) libraries via a couple of batched `grep`/`find` calls each (not one process per game), cross-referencing cover art (Steam's `library_600x900.jpg`, Prism's per-instance `profileImage/` directory) separately by id.
- Recommended row (most-recently-played — the only honest signal without a real usage-scoring system), full library grid, and one grid per launcher, all confirmed rendering real games with real cover art.
- Search (shared with the other tabs) filters *within* each section rather than collapsing the layout.
- Adapter model is "one more Process block per launcher" in `GamesLibrary.qml`, not a plugin/script-file system — Lutris/Heroic aren't installed on this machine, so a heavier abstraction would be speculative. Adding one later is still a small, contained change.

### Files tab — built (v1; flagged for a future redesign pass)
- `FilesTab.qml`: `Qt.labs.folderlistmodel`'s `FolderListModel` backs both a left-side subfolder list + breadcrumb and a right-side grid of the current directory's full contents, defaulting to `$HOME`.
- v1 is a single navigable pane (descend/ascend), not a full expand/collapse multi-level tree — a real tree is more UI work than this pass needed, and this tab was explicitly called out for further design discussion before going further.
- Search filters the tree/grid in place via `nameFilters`, and separately surfaces matches *outside* the current directory as a flat path list via one bounded `find -iname` call (substring matching, not true fuzzy scoring).

### Themes tab — built
- Top row cycles installed themes (reuses `ThemeState`/`ThemeLoader` as-is, no new discovery).
- Second row shows the *active* theme's available wallpaper files (`ThemeEntryLoader`'s wallpaper-file discovery, `find`-based, excludes shader `.frag`/`.qsb` sources) and lets you pick one — `ThemeState.wallpaperOverrides` persists the choice per-theme, and `Theme.qml`'s `wallpaper` facade resolves it ahead of the theme.json-declared default (engine inferred from the picked file's extension). Confirmed live: picking a wallpaper takes effect immediately and survives switching to the other theme and back.
- No settings section: no `theme.json` currently declares any configurable options, so a generic toggle/dropdown-schema renderer would be untested speculative plumbing for zero real consumers — deferred until a theme actually wants to declare one, consistent with "colors-only theme has no settings."

### Icon/visual polish pass — built
- `ThemedIcon.qml` — `MultiEffect`-based macOS-style tinting (desaturate + colorize toward the active theme's accent) wraps every app icon in the Applications tab, replacing plain `IconImage`.
- Files tab folders/files render as themed Nerd Font glyphs (`` / ``) instead of relying on system icon-theme lookups per file type — sidesteps the "no icon theme installed" problem entirely for that tab and gives consistent, always-themed results.
- Translucent backgrounds (`ThemeDefaults.alpha(base02, 0.5)`) added behind Files-tab grid icons and Games-tab cover-art fallbacks, replacing solid fills.
- The old default/fallback icon for icon-less entries was replaced with a themed glyph rather than the generic broken-image look.

### Found and fixed along the way
- No icon theme package was actually installed system-wide (only cursor themes + empty `hicolor`) — every named-icon lookup across the *whole launcher*, not just the new tabs, was silently falling back to blank/generic icons despite `gsettings` already claiming "Adwaita". Added `adwaita-icon-theme` to `packages.nix` — needs `nh os switch` to take effect.
- `Image.source` needs a bare filesystem path, not a constructed `file://` URL, to handle names with spaces/brackets correctly (Prism instance "Arcadia [RPG] new" broke outright with the URL form even after percent-encoding).
- **Three-stage `Loader`/height bug**, all in `Launcher.qml`'s per-tab `Loader`s:
  1. Explicit `height: item.height` on a `Loader` fights Qt's own default behavior (a sized `Loader` force-resizes its loaded item to match) — created a feedback loop that froze `ThemesTab`'s height at 0 despite `implicitHeight` correctly computing 128.
  2. First fix attempt (`implicitHeight: root.height` inside `GamesTab`/`FilesTab`) was itself a genuine binding loop — `Item.height`'s own implicit default binding *is* `implicitHeight`, so anything that makes `implicitHeight` depend on `height`, even indirectly, silently freezes. Fixed by computing height once into an independent `readonly property real computedHeight` and binding both `height` and `implicitHeight` to that same property.
  3. After removing the `Loader`'s explicit height entirely, switching through tabs in sequence showed heights accumulating (Files 1286px, Apps 1654px) rather than resetting — an inactive `Loader`'s reported height wasn't reliably snapping back to 0. Fixed with `visible: active` on each `Loader`, since `Column` excludes invisible children from its layout sum regardless of their reported size. Verified live across a full Themes→Games→Files→Apps→Apps switch cycle with no accumulation.

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
