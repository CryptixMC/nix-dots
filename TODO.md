# TODO / Roadmap

Living roadmap for the Quickshell desktop (bar, launcher, greeter, theme system) and its remaining app-theming/ecosystem threads. Tree first for a 30-second scan, details below. `[x]` = shipped, `[~]` = designed but not built, `[ ]` = open thread.

## Tree

- **Shell & Theme System**
  - [x] Folder-based theme registry — `ultraviolet` + `catppuccin`, runtime-discovered ([§1](#1-theme-system))
  - [x] Wallpaper engine — static / gif / shader, per-theme, fullscreen-pause
  - [x] Live-sync: Hyprland borders, Ghostty colors, Zed chrome
  - [ ] Zen browser theming — real preset found, genuinely can't be added risk-free without a profile-migration decision (confirmed via a real eval assertion, not just a hunch — see §1)
  - [ ] Claude Desktop theming — hard limitation, documented not chased
  - [x] Runtime theme-switcher UI — the Launcher's Themes tab ([§3](#3-launcher-tabs))
- **Bar**
  - [x] Waybar + Walker fully retired, Quickshell is the only shell
  - [x] Swappable per-icon popup (`BarIcon.popupComponent`)
  - [x] Network switcher flyout — click Wi-Fi icon, see/connect to known + open networks, password prompt for new secured ones, `nmtui` escape hatch
  - [x] Bluetooth device flyout — click icon, connect/disconnect known devices, `blueman-manager` escape hatch for pairing new ones
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
  - [x] Brightness sysfs read confirmed safe under the `greeter` user — world-readable, no ACL issue ever existed
  - [x] Lock screen v1 built — `WlSessionLock` + real PAM (password/fingerprint), **deliberately not wired to any trigger yet** ([§5](#5-lock-screen))
- **Fingerprint / PAM** — architectural ceiling, prior art, security note; `pam_fingwit` confirmed not packaged in nixpkgs, not chased further ([§2](#2-fingerprint--pam))
- **AI Workstation** — eGPU-aware hardware state feeding [Qubi](https://github.com/CryptixMC/qubi)'s model routing ([§7](#7-ai-workstation))
  - [x] Phase 1a: eGPU hotplug hardening — kernel pin, undock-during-game guard, dead-config cleanup, headless ROCm compute verified live
  - [x] Phase 1b: the state-file bridge (`ai-workstation.nix`) into Qubi — dock/undock sync, gaming-time VRAM eviction, all live-tested end to end
  - [ ] Gaming path (`SUPER+G`) — state-write logic tested manually, full launch→play→exit cycle not yet run
  - [ ] Phase 1a remainder — D3 (docked) compute control, undocked clean-boot check, D3 surprise-unplug, suspend/resume
  - Qubi's own roadmap (chat overlay, model routing, ACP backend, voice, ...) now lives in [its own repo](https://github.com/CryptixMC/qubi)
- **Reference** — Omarchy, other Quickshell shells worth reading ([§6](#6-reference-repos))

---

## 1. Theme system

Everything pulls from `themes/<name>/{base16.yaml, theme.json?, wallpapers/, components/?}`. `base16.yaml` is mandatory and feeds both Stylix (build-time) and Quickshell (runtime, via `yq`). `theme.json` and `components/` are optional — a colors-only theme is valid (`ultraviolet` ships neither).

**Live-synced today** (no rebuild needed, flips the instant `ThemeState.setTheme()`/`cycleTheme()` runs):
- Hyprland active/inactive border colors (`hyprctl eval` + `hl.config(...)`, since this repo's Lua config backend doesn't support `hyprctl keyword`)
- Ghostty terminal colors, via a `config-file` include Ghostty always loads after its own `theme = stylix` baseline
- Zed **chrome only** (background/borders/tabs/panels/terminal ANSI) — written to `~/.config/zed/themes/quickshell-live.json` using Stylix's own generated `stylix.json` as the 141-key structural template. Syntax-highlighting colors and player-cursor colors deliberately stay static (whatever Stylix last generated for `ultraviolet`) — full syntax remapping is a lot of extra surface for a cosmetic win where the editor buffer itself is a small fraction of the screen most of the time.

**Zed's build-time half**: `zed.nix` sets `theme = lib.mkForce "Quickshell Live"`, overriding Stylix's own `theme = "Base16 <name>"` default. Needs `nh home switch` once to take effect (untested this pass whether an already-open Zed window hot-reloads the *content* of a custom theme file it already has selected — Zed's settings.json hot-reload is well-established, but a referenced theme file's content re-reading on change is a separate, unconfirmed mechanism).

**Zen browser — real option confirmed, genuinely can't be added risk-free**: `nix eval` against the live flake confirms `programs.zen-browser.profiles.<name>.presets.catppuccin.{enable,accent,flavor}` are real options (accent: 14 named colors, flavor: Frappe/Latte/Macchiato/Mocha) using the real `catppuccin/zen-browser` userChrome theme, not just GTK inheritance. Tried adding it as a second, `isDefault = false` profile alongside the existing self-managed live one (`~/.config/zen/huedeu9v.Default Profile`) — reverted after a real eval failure: the module hard-asserts "exactly one default Zen profile" the instant *any* profile is declared, with no concept of the pre-existing external profile to count against that assertion. So `isDefault = false` alone doesn't evaluate, and `isDefault = true` risks changing which profile actually launches by default. There's no zero-risk path here without first deciding how to bring the live profile under home-manager's management (name it explicitly, or accept the migration) — confirmed by evidence now, not just a hunch. Baseline GTK dark-mode (`gsettings ... prefer-dark`, already set in `hyprland.nix`'s autostart) covers native dialogs regardless.

**Claude Desktop**: Electron, no settings hook, no Stylix target. Only lever is GTK dialog chrome inheriting the system dark theme (already happening). Content-level theming isn't achievable from the Nix side — documented limitation, not a bug to keep chasing.

---

## 2. Fingerprint / PAM

- [x] Shortened fprintd timeout for `sudo`/TTY `login` (`modules/nixos/services/fprintd.nix`: `timeout = 5; max-tries = 2`). Explicitly disabled for `sshd` and `greetd`.
- **Architectural ceiling**: PAM's conversation model is sequential for a plain terminal — whichever module runs first blocks until success/timeout. No stock "race both, take whichever's ready."
- **Real prior art for a proper fix**: [Fingwit](https://github.com/xapp-project/fingwit)'s `pam_fingwit.so` — decides at runtime whether a scan is likely to succeed, skips straight to password if not, instead of blocking on a doomed read.
  - [ ] Evaluate swapping in `pam_fingwit.so` in place of the flat timeout. Checked: **not packaged in nixpkgs** under any name (`nix eval`'s own "did you mean 'finit'?" confirms no close match). Packaging an unfamiliar, security-sensitive PAM module blind (no way to test-drive it without risking login/sudo) isn't something to attempt autonomously — stays a real "someone needs to sit down and package + test this deliberately" item, not chased further.
- **Security note**: [CVE-2024-37408](https://linuxsecurity.com/news/security-projects/fingwit-biometric-authentication) — fingerprint-only auth on `su`/`sudo`/`polkit` can let a background process obtain privileges without a real scan prompt. Read before making fingerprint more automatic/prominent anywhere.
- The greeter's PAM conversation (via `Quickshell.Services.Greetd`) is genuinely sequential too — real concurrent fingerprint+password at the greeter isn't achievable without driving the PAM conversation directly (`Quickshell.Services.Pam`), which is architecturally a lock-screen-shaped project (see §5, now built) — not a greeter tweak.

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
- [x] Brightness status icon's `/sys/class/backlight/.../brightness` read — checked directly: `/sys/class/backlight/intel_backlight/brightness` is `root:root`, mode `644` (world-readable). No seat ACL or `video`-group membership is needed for a plain read regardless of which user owns the session — closes this out, no fix was ever needed.

---

## 5. Lock screen

Architecturally nothing like the greeter — greetd/cage only run **pre-login**. A lock screen has to run **inside the already-authenticated session**, using `Quickshell.Wayland`'s `WlSessionLock` / `WlSessionLockSurface` (`ext-session-lock-v1` — confirmed present in the installed Quickshell 0.3.1 qmltypes).

### v1 built (2026-09-12) — deliberately not wired to any trigger yet

- `quickshell/modules/lock/{LockService.qml, LockView.qml, qmldir}` + `modules/nixos/services/quickshell-lock.nix` (new PAM service).
- `LockService.qml` drives `Quickshell.Services.Pam`'s `PamContext` directly (not `Quickshell.Services.Greetd` — that's greetd's own separate pre-login protocol) against a new `security.pam.services.quickshell-lock` service. Phase machine (idle/prompting/authenticating/failed) mirrors `quickshell-greeter/modules/auth/AuthState.qml`'s proven-live shape, adapted to `PamContext`'s API (confirmed via the installed qmltypes, not guessed): `config`, `user`, `message`, `responseRequired`/`responseVisible`, signals `completed(result)`/`error`/`pamMessage`, methods `start()`/`abort()`/`respond()`.
- The PAM service declaration is a bare `security.pam.services.quickshell-lock = {};` — confirmed via a real build that this alone produces a correct, complete stack (`pam_fprintd.so` sufficient, falling through to `pam_unix.so` for password, `pam_deny.so` otherwise) — `fprintd.nix`'s existing blanket `fprintAuth` default applies automatically, so fingerprint-or-password comes for free without saying so explicitly.
- `LockView.qml` (per-screen lock surface content, parented onto `WlSessionLockSurface.contentItem`): clock, prompt/error text, password field. v1 background is a flat themed color, not the full `Wallpaper.qml` engine — that component is tightly coupled to being its own `PanelWindow`, not something to re-parent into a lock surface's content item for this pass. No Escape-to-dismiss anywhere, unlike every other overlay in this repo — a lock screen must not be dismissible without real authentication.
- **Deliberately shipped inert**: nothing calls `LockService.lock()` from a keybind, idle timeout, or `loginctl lock-session` handler. The only trigger is a manual IPC call (`quickshell ipc call lock lock`) registered in `shell.qml`, meant to be run by hand once someone's ready to test the unlock path. A broken unlock path here has real consequences — getting stuck at a lock screen with no way back in — so this stays complete-but-untested-live rather than auto-wired, exactly the "build a switchable copy, don't make it live" treatment this kind of change needs.
- **Likely resolved via a local-model investigation, not yet a live test**: whether `pam.start()` can just be called again directly after a `Failed` completion, or needs `active` toggled first. §7's local coding-agent had `qwen2.5-coder:7b` read the real `quickshell-service-pam.qmltypes` and this file directly (no hints given) — neither `start`'s nor `active`'s type signature documents a reset requirement, and it concluded (high confidence, but from type signatures alone, not a live PAM conversation) that calling `pam.start()` directly is fine. Treat this as strong supporting evidence, not a replacement for actually testing the unlock path live — still confirm on the very first real test.
- Not carried over from Omarchy's reference (`shell/plugins/lock/Service.qml`/`LockView.qml`, ~840 lines total) since that source wasn't locally fetchable this session, so this is an original implementation grounded in the real Quickshell APIs rather than a port: stranded-lock recovery, a stabilize-timer before engaging, DPMS/idle reconciliation per monitor, and animated/video backgrounds are all still open — real ideas worth revisiting once the core password/fingerprint flow has been tested live at least once.

---

## 6. Reference repos

- **[Omarchy](https://github.com/omacom/omarchy)** (branch `quattro`) — real Quickshell-based shell with a genuine plugin architecture (`shell/plugins/*/manifest.json` + isolated QML). Coupling to Omarchy-specific behavior mostly shows up as external CLI calls rather than embedded logic, so most of it is reference/re-derive material rather than drop-in — the lock screen (§5) is the one piece confirmed directly adoptable near-verbatim. No tab-based launcher there (its menu is a hierarchical drill-down, not Spotlight-style tabs) — the launcher tab design (§3) is original.
- **[doannc2212/quickshell-config](https://github.com/doannc2212/quickshell-config)** — Ã  la carte reference bundling a status bar, launcher, notification daemon, and a runtime theme switcher with 206 bundled themes. Concrete prior art if the Themes tab (§3) grows a "browse community themes" feature later.
- **[SirAllap/quickshell-popups](https://github.com/SirAllap/quickshell-popups)** — theme-aware popup widgets including an existing `custom/claude-usage` module — prior art if a Claude-usage bar widget ever gets built.
- [Hyprland wiki: App Launchers](https://wiki.hypr.land/Useful-Utilities/App-Launchers/) / [Status Bars](https://wiki.hypr.land/Useful-Utilities/Status-Bars/) — general ecosystem, worth periodic re-checking.

---

## 7. AI Workstation

Goal: this laptop's actual hardware state (an AMD RX 6800 XT eGPU that's only sometimes attached over Thunderbolt) drives model routing for **Qubi**, the local-AI assistant that used to be built here but is now [its own repo](https://github.com/CryptixMC/qubi), standalone at `~/Projects/qubi`. What stays here is genuinely host-specific: the eGPU/Thunderbolt hardening itself (`amd.nix`) and the small state-file bridge (`ai-workstation.nix`) that tells Qubi which model tier to use, written on every dock/undock event. Qubi's own design, reliability findings, Goose/ACP tuning, and chat-overlay development are now [Qubi's development log](https://github.com/CryptixMC/qubi/blob/main/docs/development-log.md) — this section no longer duplicates them. Full plan/findings log for the original build: `~/.claude/plans/lets-work-on-this-quizzical-crane.md`.

### Phase 1a — eGPU hotplug hardening — built
- `modules/nixos/hardware/amd.nix` already had a working hotplug system (udev rules on PCI vendor/device ID, `egpu-bar-fix.service`, `egpu-eject.service`, AER/ASPM kernel-param workarounds) — this pass closed specific gaps rather than building from scratch.
- `boot.kernelPackages` pinned to `pkgs.linuxPackages_6_18` (verified via `nix eval` to be a no-op today, 6.18.50 either way) — stops a future `nix flake update` from silently shifting the kernel out from under the Thunderbolt/amdgpu workarounds.
- `egpuEjectScript` gained a Stage 1.5: refuses to eject (clear `hyprctl notify` instead) if `gamescope` is running, since a live game's own DRM context could hang the unbind same as ROCm's.
- Deleted `modules/nixos/apps/ollama.nix` — dead, unimported, hardcoded `acceleration = "cuda"` (wrong for this AMD-only host). Live config is `modules/nixos/services/ollama.nix`.
- **Live-verified**: ROCm compute genuinely lands on the eGPU with zero displays attached to it (`ollama ps` → `100% GPU`) — closes the one gap the codebase's own comments flagged as never actually checked. Surprise-unplugging the cable (no `SUPER+SHIFT+U`) in that same headless state did **not** hang Hyprland — the primary safety bar for that state held.

### Found and fixed along the way (Phase 1a)
- **The udev backstop doesn't reliably re-fire after a crash.** After the surprise-unplug above, `egpu-eject.service` never fired via its remove-triggered udev rule at all (kernel handled teardown solo, with real but non-fatal errors: `ring kiq test failed`, a `GPU reset` that failed, a kernel `WARNING` in `kfd_device_queue_manager.c`). Reattaching later in the same boot, `egpu-bar-fix.service`'s add-triggered rule *also* didn't fire (`udevadm info` showed `USEC_INITIALIZED` still pointing at the original attach, not the reattach) — the kernel rebinds the driver natively either way, so it looks like everything's fine, but none of the higher-level automation runs.
- **Root cause: a crashed removal leaves ROCm/KFD compute dead, not just the udev events.** `rocminfo` post-crash showed *zero* GPU agents despite `amdgpu` being cleanly bound with a valid BAR — display/PCI-level recovery is cosmetic, compute is gone until reboot. This is also why a model actively loaded at the moment of removal leaves an **unkillable orphaned `llama-server` process** (survives both `systemctl restart` and a full `systemctl stop` of `ollama.service`, despite correct `KillMode=control-group`) — it's genuinely stuck on a kernel-level wait for hardware that vanished.
- Practical upshot: "reboot after any surprise/crashed eGPU removal" is a hard requirement for this whole automation stack to be trustworthy, not a nice-to-have. Not yet turned into an automated health check (e.g. comparing `rocminfo` agent count against `lspci` GPU presence) — worth doing before leaning on this further.

### Phase 1b — the state bridge into Qubi — built
- `modules/nixos/apps/ai-workstation.nix`: `/run/ai-workstation/state.json` (tmpfs, re-derived every boot — no impermanence exists in this repo so nothing else needed persisting), `ai-workstation-{dock,undock}-sync.service` oneshots that write the docked/undocked model tag, scoped NOPASSWD sudo rules mirroring the existing `egpu-eject` pattern.
- Hooked into `amd.nix`'s existing `egpu-bar-fix`/`egpu-eject` scripts (fire-and-forget, `--no-block`) and the `SUPER+G` gaming keybind, reusing the same eGPU detection rather than building a second one.
- **Live-verified end to end**: state file write → Qubi's config reconciliation → desktop notification, for both dock and undock paths, on real hardware.
- Everything downstream of the state file — Goose config generation, model selection, extension/recipe tuning, the chat overlay, ACP backend — is now Qubi's own concern; see [Qubi's development log](https://github.com/CryptixMC/qubi/blob/main/docs/development-log.md) for that history, including the real PATH/sudo/yq bugs found wiring the two together.

### Still open
- **Reboot to clear the live stuck `llama-server` D-state process documented above** — genuinely blocking (can't be done autonomously without the user present).
- End-to-end test `SUPER+G` through a real Steam/gamescope launch — `ollama stop` VRAM eviction and post-game state reconciliation are only unit-tested so far.
- Finish the deferred Phase 1a checklist (D3 compute control, undocked clean-boot check, D3 surprise-unplug, suspend/resume) — genuinely needs physical eGPU docking/undocking and a real suspend/resume cycle, none of which are autonomously doable.
- Live-trigger the lock screen end to end (with the user physically present to actually unlock it) — structurally checked but never actually invoked, deliberately.

---

## 8. Bar widgets — click-driven flyouts

Same upgrade `Volume.qml` already got over launching `pavucontrol` directly, applied to the other two bar icons that previously just shelled out to an external app on click.

- **Network** (`NetworkPopup.qml`): lists `Quickshell.Networking` Wi-Fi networks sorted by signal strength, real API confirmed via the installed qmltypes (`Network.{connect,disconnect,forget}`, `WifiNetwork.{signalStrength,security,connectWithPsk}`, `WifiDevice.scannerEnabled` toggled on while the popup's open so the list reflects a live scan, not a stale cache). Known networks and open/OWE ones connect with one click; an unknown secured network expands an inline password field in place (`connectWithPsk`) instead of a separate dialog. `nmtui` stays one click away via a "›" link for anything this doesn't cover (hidden SSIDs, enterprise auth).
- **Bluetooth** (`BluetoothPopup.qml`): lists already-known/paired devices (`adapter.devices`) with click-to-connect/disconnect and battery percentage where available. Pairing a genuinely new device isn't covered — `BluetoothAdapter` has no direct discovery-trigger method in this API (only a read-only `discovering` status), so a real scan/pair UI wasn't buildable this pass without something to drive it; `blueman-manager` is the escape hatch for that case instead of a half-built pairing flow.
- Both follow `VolumePopup.qml`'s exact structural pattern (`PopupWindow`, `HoverHandler`-driven auto-close, `BarIcon.onClickFn` toggle) — no new popup architecture introduced.
- Validated via `qmllint` (no hard errors, only the same import-path noise the whole codebase's Quickshell-typed files produce under a bare invocation — confirmed by running it against the already-shipped `Launcher.qml` for comparison) and a full `nix flake check`/`nixos-rebuild build`. Not yet clicked on a real screen.
