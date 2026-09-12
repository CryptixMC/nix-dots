pragma Singleton
import QtQuick

// Deliberately a separate, trimmed copy of the tokens actually needed here
// — not an import of quickshell/theme/Colors.qml. The greeter runs as an
// unprivileged pre-login system service; keeping it decoupled from the
// daily-driver shell means an in-progress edit to the desktop bar/launcher
// can never affect the login screen. Values are hand-picked to roughly
// match the desktop's palette (same accent purple), not bridged/generated
// from it — visual drift over time is an accepted tradeoff, see TODO.md §2.
QtObject {
    readonly property color bg: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.97)
    readonly property color fg: "#f5f5f5"
    readonly property color mutedFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.55)

    readonly property color accentPurple: "#b047ff"
    readonly property color errorRed: "#ff5d5d"

    readonly property color inputBg: "#0c0c0f"
    readonly property color inputBorder: "#9150ff"
    readonly property color panelBorder: "#1c1c1c"
    // Distinctly lighter than `bg` (the full-window background) so a panel
    // rendered on top of it — e.g. NetworkPanel — is actually visible.
    readonly property color panelBg: Qt.rgba(18 / 255, 18 / 255, 22 / 255, 0.98)

    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property int fontSizeBase: 14
    readonly property int fontSizeLarge: 20

    // Filename only (relative to theme/wallpapers/) — a static copy of the
    // main shell's catppuccin animated wallpaper, reused rather than
    // sourcing anything new (see modules/greeter/Wallpaper.qml). Not
    // theme-registry-driven like the main shell's wallpapers — this is a
    // fixed decoupled asset, same rationale as the rest of this file.
    readonly property string wallpaperFile: "greeter.gif"
    // Overlay atop the wallpaper, more transparent than `bg` so the
    // wallpaper actually reads as visible behind the login UI.
    readonly property color bgOverlay: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.55)
}
