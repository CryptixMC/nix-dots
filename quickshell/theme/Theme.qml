pragma Singleton
import QtQuick
import Quickshell

// Facade over ThemeLoader's discovered/assembled theme entries. Quickshell
// renders before ThemeLoader's async discovery+yq+FileView chain resolves,
// so `fallback` (built from ultraviolet's real base16 values, via the same
// ThemeDefaults.build() every theme goes through) covers that gap and any
// case where the active theme folder is ever missing/broken.
QtObject {
    id: root

    readonly property var fallback: ThemeDefaults.build({
        base00: "050505", base01: "080808", base02: "0f0f0f", base03: "212121", base04: "373737",
        base05: "c8c8c8", base06: "e0e0e0", base07: "f5f5f5",
        base08: "ff5de0", base09: "e85cf0", base0A: "d35cf7", base0B: "c050ff",
        base0C: "b047ff", base0D: "9f4eff", base0E: "9150ff", base0F: "8850ff"
    }, ({}), ({}), `${ThemeLoader.themesDir}/ultraviolet`)

    readonly property var current: ThemeLoader.themes[ThemeState.activeThemeName]
        ?? ThemeLoader.themes[ThemeState.defaultTheme]
        ?? root.fallback

    readonly property var color: root.current.color
    readonly property var radius: root.current.radius
    readonly property var spacing: root.current.spacing
    readonly property var font: root.current.font
    readonly property var motion: root.current.motion
    readonly property var effect: root.current.effect
    readonly property var wallpaper: root.current.wallpaper
    readonly property var componentOverrides: root.current.componentOverrides ?? ({})

    // Live-syncs Hyprland's own border colors to the active theme via
    // `hyprctl keyword` (applies immediately, no Hyprland restart needed)
    // — the one non-Quickshell surface this theme system also drives live.
    // Deliberately reuses color tokens Theme.color already exposes
    // (accentPink/accentPurple/tooltipMuted) rather than adding a new
    // theme.json schema section: border colors are just another
    // consequence of the base16 palette, so no theme author action is
    // needed to get this "for free". Only accentPink/accentPurple/
    // tooltipMuted are used here specifically because they're `opaque()`
    // outputs (plain "#RRGGBB" strings) in ThemeDefaults.buildColor() —
    // alpha()-derived tokens are real Qt color values, not strings, and
    // hyprctl's keyword syntax wants bare hex.
    function hexOf(hexString) {
        return hexString.replace("#", "");
    }

    // `hyprctl keyword` is legacy-hyprlang-only and errors ("keyword can't
    // work with non-legacy parsers") against this repo's Lua-configured
    // Hyprland (see hyprland.nix's `configType = "lua"`) — confirmed by
    // testing both directly this session. `hyprctl eval` running an
    // `hl.config({...})` Lua expression is the equivalent live-apply
    // mechanism for the Lua config backend, mirroring the exact table
    // shape hyprland.nix's own static `col.active_border`/
    // `col.inactive_border` settings already use.
    function syncHyprlandBorders() {
        const from = root.hexOf(root.color.accentPink);
        const to = root.hexOf(root.color.accentPurple);
        const inactive = root.hexOf(root.color.tooltipMuted);
        const activeExpr = `hl.config({general = {["col.active_border"] = {colors = {"rgb(${from})", "rgb(${to})"}, angle = 45}}})`;
        const inactiveExpr = `hl.config({general = {["col.inactive_border"] = "rgba(${inactive}aa)"}})`;
        Quickshell.execDetached(["hyprctl", "eval", activeExpr]);
        Quickshell.execDetached(["hyprctl", "eval", inactiveExpr]);
    }

    onColorChanged: root.syncHyprlandBorders()
    Component.onCompleted: root.syncHyprlandBorders()
}
