pragma Singleton
import QtQuick

// Deliberately a separate, trimmed copy of the tokens actually needed here
// — not an import of quickshell/theme/Colors.qml. The greeter runs as an
// unprivileged pre-login system service; keeping it decoupled from the
// daily-driver shell means an in-progress edit to the desktop bar/launcher
// can never affect the login screen. Values are hand-picked to roughly
// match the desktop's palette (same accent purple), not bridged/generated
// from it — visual drift over time is an accepted tradeoff, see TODO.md §2.
//
// Restyled to the Ultraviolet design system's VIOLET role mapping, matching
// themes/ultraviolet-v2/. Hand-transcribed on purpose: importing the main
// shell's role layer here would undo the decoupling above, and locking
// yourself out of the machine is the one failure this file must never have.
// The comment beside each value names the role it stands for, so a drift
// check against themes/ultraviolet-v2/theme.json is a visual diff.
QtObject {
    readonly property color fg: "#f5f5f5"          // text-strong

    // clock-fg (base0B). Was wrongly pointed at textDim (base0F) — the real
    // bar's Clock.qml sits on the accent-labeled tier (clockFg = base0B in
    // themes/ultraviolet-v2/theme.json), not the dim tier. Clock only.
    readonly property color clockFg: "#c050ff"
    // text-body / right-module-fg (base05). The real bar's BarIcon.qml
    // default glyph colour is Theme.color.rightModuleFg, plain body-text
    // grey — accent violet is reserved for the workspace focus dot, the
    // active launcher tab, and the clock, not every icon on screen. Every
    // status icon (battery/brightness/volume/bluetooth/network) and its
    // label uses this, matching that default rather than the blanket
    // violet this file used everywhere before.
    readonly property color textBody: "#c8c8c8"
    // text-dim (base0F). Multi-purpose in the real theme — tooltipMuted,
    // moduleDisabledFg, launcherPlaceholderFg are all this same value — so
    // one token covers both uses here too: the password field's prompt
    // text, and Bluetooth's "adapter off" glyph. Was wrongly split across
    // mutedFg (base0F, right value but wrong use sites) and a disabledFg
    // this file invented at base04 (25% grey, "genuinely inert") — but the
    // real bar's Bluetooth.qml colours its off-state with moduleDisabledFg
    // (base0F), a dim violet, not the deeper textDisabled tier. There is no
    // base04 use case anywhere in this file's actual UI, so that role is
    // dropped rather than kept unused.
    readonly property color textDim: "#8850ff"

    readonly property color accentPurple: "#b047ff" // line-strong / invert-bg
    // band-selected — the violet band behind a selected/connected row. Was
    // spelled inline in NetworkPanel.qml as base0C at 12%.
    //
    // NOTE THE BYTE ORDER. Qt parses an 8-digit hex string as #AARRGGBB,
    // but tokens.css (and CSS generally) writes #RRGGBBAA — so a value
    // pasted straight across from the design system comes out as a
    // completely different colour, not merely a wrong alpha. tokens.css's
    // #8850ff2e read as Qt would give r=80 g=255 b=46: bright green.
    // Every translucent value in this file is therefore written
    // alpha-first, with the CSS spelling noted beside it.
    // The main shell doesn't need this care because ThemeDefaults.resolveRef()
    // converts CSS order explicitly; here it is hand-transcribed.
    readonly property color bandSelected: "#2e8850ff" // css #8850ff2e

    // critical. Was #ff5d5d, a true red that appears nowhere in the base16
    // ramp; base08 keeps failed auth inside the palette and matches how
    // lock.html signals the same state on the desktop side.
    readonly property color errorRed: "#ff5de0"

    readonly property color inputBg: "#050505"     // ground — a field is a frame, not a fill
    readonly property color inputBorder: "#b047ff" // line-strong
    // line — violet hairline. Alpha-first, see the byte-order note above.
    readonly property color panelBorder: "#5c8850ff" // css #8850ff5c

    // Same ground as everything else. A panel reads as a panel because of the
    // hairline border above, not because it is a lighter box — that is the
    // design system's "a panel is a drawn frame, not a card". Opaque, since
    // depth here comes from the frame rather than from translucency.
    readonly property color panelBg: "#050505"

    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property int fontSizeBase: 14
    readonly property int fontSizeLarge: 20

    // The FALLBACK wallpaper only, used when Wallpaper.qml has no live
    // snapshot to read yet (fresh install, before cryptix's desktop session
    // has ever run its sync — see Theme.qml's syncGreeterWallpaper() and
    // this repo's greetd.nix tmpfiles rule). Once that snapshot exists,
    // this file is bypassed entirely in favour of whatever the desktop
    // session's actual wallpaper is, animated or not.
    //
    // Filename only (relative to theme/wallpapers/) — a fixed decoupled
    // copy, not theme-registry-driven, same rationale as the rest of this
    // file. ultraviolet-v2's own still, not its orbital gif: greetd.nix
    // copies this whole tree into the store with lib.cleanSource, so the
    // asset's size is paid on every rebuild — 2.8 MB for the still against
    // 23 MB for the gif, for a fallback that, once the sync has run once,
    // is never actually shown again. The previous greeter.gif was a copy of
    // catppuccin's animated wallpaper and now reads wrong against a violet
    // login screen; it is left in place but unused, and is safe to delete.
    readonly property string wallpaperFile: "alyssa.png"
    // Overlay atop the wallpaper, transparent enough that the wallpaper still
    // reads behind the login UI.
    readonly property color bgOverlay: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.55)
}
