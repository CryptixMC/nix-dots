pragma Singleton
import QtQuick

// Hand-copied palette, not imported from the desktop shell, so an in-progress
// shell edit can never break the login screen. Comments name each value's role
// in desktop/themes/ultraviolet-v2/theme.json for drift checks (TODO.md §4).
QtObject {
    readonly property color fg: "#f5f5f5"          // text-strong

    // clock-fg (base0B)
    readonly property color clockFg: "#c050ff"
    // text-body (base05): status icons and labels.
    readonly property color textBody: "#c8c8c8"
    // text-dim (base0F): placeholder text and disabled glyphs.
    readonly property color textDim: "#8850ff"

    readonly property color accentPurple: "#b047ff" // line-strong / invert-bg
    // band-selected. Qt reads 8-digit hex as #AARRGGBB, not CSS #RRGGBBAA,
    // so translucent values here are alpha-first with the CSS spelling noted.
    readonly property color bandSelected: "#2e8850ff" // css #8850ff2e

    // critical (base08)
    readonly property color errorRed: "#ff5de0"

    readonly property color inputBg: "#050505"     // ground — a field is a frame, not a fill
    readonly property color inputBorder: "#b047ff" // line-strong
    // line
    readonly property color panelBorder: "#5c8850ff" // css #8850ff5c

    // Same ground as everything else; the hairline border marks the panel.
    readonly property color panelBg: "#050505"

    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property int fontSizeBase: 14
    readonly property int fontSizeLarge: 20

    // Fallback wallpaper (in theme/wallpapers/) until the desktop session's
    // snapshot exists. The still, not the gif, to keep the store copy small.
    readonly property string wallpaperFile: "alyssa.png"
    // Semi-transparent so the wallpaper shows through.
    readonly property color bgOverlay: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.55)
}
