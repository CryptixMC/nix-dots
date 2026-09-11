pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Facade over ThemeLoader's discovered/assembled theme entries. Quickshell
// renders before ThemeLoader's async discovery+yq+FileView chain resolves,
// so `fallback` (built from ultraviolet's real base16 values, via the same
// ThemeDefaults.build() every theme goes through) covers that gap and any
// case where the active theme folder is ever missing/broken.
//
// Rooted as a plain Item (not QtObject) because the Ghostty sync below
// needs a FileView child — same reasoning as ThemeState.qml/ThemeLoader.qml.
Item {
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

    readonly property var base16: root.current.base16
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

    // Live-syncs Ghostty's colors to the active theme. Ghostty has no
    // "set config value" IPC — the mechanism is a config-file include:
    // ghostty.nix's settings declare `config-file =
    // "?~/.local/state/quickshell-ghostty-theme.conf"` (the `?` means
    // "don't error if missing"), and per Ghostty's own documented
    // load-order semantics, an included file's directives always apply
    // *after* the rest of the file that included it — so this always wins
    // over the `theme = stylix` baseline in ghostty.nix regardless of
    // where the config-file line falls textually. Palette uses the
    // standard base16-to-ANSI-16 convention (0/8=base00/03 black,
    // 1/9=base08/08 red, ... 7/15=base05/07 white) — confirmed against
    // Theme.base16 (the raw per-theme palette, not the semantic
    // Theme.color remapping, since a real 16-slot terminal palette needs
    // all 16 base16 slots).
    //
    // Any newly-opened Ghostty window picks this up immediately (config is
    // read at window-open time) — confirmed by reading Ghostty's own
    // startup log during testing. Whether Ghostty's `reload-config` D-Bus
    // action (org.gtk.Actions on com.mitchellh.ghostty, confirmed to
    // exist and be callable without error) actually live-refreshes an
    // *already-open* window wasn't reliably confirmed in this session's
    // testing — firing it here is harmless best-effort either way, but
    // don't take it as a guarantee; ctrl+shift+, is Ghostty's own default
    // reload-config keybind if a manual nudge is ever needed.
    function ghosttyConfText() {
        const b = root.base16;
        if (!b || !b.base00)
            return "";
        return [
            `background = ${b.base00}`,
            `foreground = ${b.base05}`,
            `cursor-color = ${b.base05}`,
            `selection-background = ${b.base02}`,
            `selection-foreground = ${b.base05}`,
            `palette = 0=#${b.base00}`,
            `palette = 1=#${b.base08}`,
            `palette = 2=#${b.base0B}`,
            `palette = 3=#${b.base0A}`,
            `palette = 4=#${b.base0D}`,
            `palette = 5=#${b.base0E}`,
            `palette = 6=#${b.base0C}`,
            `palette = 7=#${b.base05}`,
            `palette = 8=#${b.base03}`,
            `palette = 9=#${b.base08}`,
            `palette = 10=#${b.base0B}`,
            `palette = 11=#${b.base0A}`,
            `palette = 12=#${b.base0D}`,
            `palette = 13=#${b.base0E}`,
            `palette = 14=#${b.base0C}`,
            `palette = 15=#${b.base07}`
        ].join("\n") + "\n";
    }

    function syncGhosttyTheme() {
        const text = root.ghosttyConfText();
        if (text.length === 0)
            return;
        ghosttyFile.setText(text);
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "com.mitchellh.ghostty", "--object-path", "/com/mitchellh/ghostty", "--method", "org.gtk.Actions.Activate", "reload-config", "[]", "{}"]);
    }

    FileView {
        id: ghosttyFile
        path: `${Quickshell.env("HOME")}/.local/state/quickshell-ghostty-theme.conf`
        watchChanges: false
        printErrors: false
    }

    onColorChanged: {
        root.syncHyprlandBorders();
        root.syncGhosttyTheme();
    }
    Component.onCompleted: {
        root.syncHyprlandBorders();
        root.syncGhosttyTheme();
    }
}
