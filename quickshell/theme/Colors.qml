pragma Singleton
import QtQuick

// Hardcoded 1:1 copy of the palette/type scale from
// modules/home-manager/wm/waybar.nix's `style` string. Not sourced from
// stylix yet — see TODO.md §3 "Stylix integration" for the later bridge plan.
QtObject {
    readonly property color barBg: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.92)
    readonly property color barBorder: Qt.rgba(33 / 255, 33 / 255, 33 / 255, 0.6)
    readonly property color fg: "#c8c8c8"

    readonly property color workspaceInactive: Qt.rgba(1, 1, 1, 0.07)
    readonly property color workspaceOccupied: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.45)

    readonly property color accentPink: "#ff5de0"
    readonly property color accentPurple: "#b047ff"
    readonly property color purpleHover: Qt.rgba(176 / 255, 71 / 255, 255 / 255, 0.88)

    readonly property color windowTitleFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.55)
    readonly property color windowSeparator: Qt.rgba(1, 1, 1, 0.07)

    readonly property color clockFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.65)

    readonly property color rightModuleFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.52)

    readonly property color tooltipBg: Qt.rgba(6 / 255, 6 / 255, 9 / 255, 0.98)
    readonly property color tooltipBorder: Qt.rgba(33 / 255, 33 / 255, 33 / 255, 0.95)
    readonly property color tooltipMuted: "#505050"
    readonly property color tooltipFg: Qt.rgba(245 / 255, 245 / 255, 245 / 255, 0.8)

    // Dim state for a module that's present but disabled (e.g. bluetooth
    // adapter powered off) — distinct from an inactive-but-enabled state.
    readonly property color moduleDisabledFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.25)

    // Confirmed via `fc-list | grep -i jetbrains` + a side-by-side
    // screenshot with waybar: the plain "JetBrainsMono Nerd Font" family
    // doesn't carry the icon glyph set Qt resolves to here — Qt fell back
    // to a color emoji font for the Nerd Font PUA codepoints, rendering
    // every right-module icon as a blurry colored blob instead of a crisp
    // glyph. "...Nerd Font Mono" is the exact family waybar.nix's CSS and
    // stylix.nix's fonts.monospace.name both already use — matching it
    // fixed the icons.
    readonly property string fontFamily: "JetBrainsMono Nerd Font Mono"
    readonly property int fontSizeBase: 13
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeWorkspace: 8

    readonly property int barHeight: 26
    readonly property int trayIconSize: 15
    readonly property int tooltipHoverDelayMs: 400
}
