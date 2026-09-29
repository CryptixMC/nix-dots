pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/wallpaper/scenes/registry.js" as SceneRegistry

// Facade over ThemeLoader's theme entries. `fallback` (ultraviolet's base16 via
// ThemeDefaults.build()) covers the gap before async loading resolves or when the
// active theme folder is broken. Item root because it needs FileView children.
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

// False until the active theme has loaded; until then `current` is `fallback`,
// which uses baseline role mappings. Large surfaces painted in a remapped role
// gate on this to avoid a colour flash (see Orbital.qml).
    readonly property bool resolved: ThemeLoader.themes[ThemeState.activeThemeName] !== undefined
        || ThemeLoader.themes[ThemeState.defaultTheme] !== undefined

    readonly property var base16: root.current.base16

// Surface backgrounds alpha-scaled by ThemeState.menuTranslucent; applied here so
// it stays a session preference rather than per-theme.
    readonly property var _translucentBgTokens: ["barBg", "tooltipBg", "launcherBg"]
    readonly property real _menuTranslucentAlphaFactor: 0.75

    function _asRgba(v) {
        // alpha() yields a Qt color, opaque() a bare "#RRGGBB" string; handle both.
        if (typeof v === "string") {
            const rgb = ThemeDefaults.hexToRgb(v);
            return { r: rgb.r, g: rgb.g, b: rgb.b, a: 1.0 };
        }
        return { r: v.r, g: v.g, b: v.b, a: v.a };
    }

    function _applyTranslucency(colorMap) {
        if (!ThemeState.menuTranslucent)
            return colorMap;
        const out = Object.assign({}, colorMap);
        for (const key of root._translucentBgTokens) {
            const raw = out[key];
            if (raw === undefined || raw === "transparent")
                continue;
            const c = root._asRgba(raw);
            out[key] = Qt.rgba(c.r, c.g, c.b, c.a * root._menuTranslucentAlphaFactor);
        }
        return out;
    }

    readonly property var color: root._applyTranslucency(root.current.color)
    readonly property var radius: root.current.radius
    readonly property var spacing: root.current.spacing
    readonly property var font: root.current.font
    readonly property var motion: root.current.motion
    readonly property var effect: root.current.effect
    readonly property var qubi: root.current.qubi ?? ({})
    // Every registry scene is pickable from every theme, unlike `w.available`.
    readonly property var availableScenes: SceneRegistry.scenes

    // Applies a user wallpaper override ahead of the theme.json default. Scene
    // names are checked first since they aren't files; otherwise the engine follows
    // the file extension (only images/gifs are offered as overrides).
    function resolveWallpaper(w, themeName) {
        const overrideFile = ThemeState.wallpaperOverrides[themeName];
        if (!overrideFile)
            return w;
        if (SceneRegistry.names.includes(overrideFile))
            return Object.assign({}, w, { engine: "scene", scene: overrideFile });
        if (!w.available || !w.available.includes(overrideFile))
            return w;
        const isGif = overrideFile.toLowerCase().endsWith(".gif");
        return Object.assign({}, w, {
            engine: isGif ? "gif" : "static",
            image: isGif ? w.image : overrideFile,
            gif: isGif ? overrideFile : w.gif
        });
    }
    readonly property var wallpaper: root.resolveWallpaper(root.current.wallpaper, ThemeState.activeThemeName)
    readonly property var componentOverrides: root.current.componentOverrides ?? ({})

    // Pushes the hyprBorder* tokens to Hyprland live. hyprctl wants bare RRGGBBAA,
    // but Qt stringifies alpha colors as "#AARRGGBB", so move the alpha pair to the end.
    function hyprHex(color) {
        const s = String(color).replace("#", "");
        return s.length === 8 ? s.substring(2) + s.substring(0, 2) : s + "ff";
    }

    // `hyprctl keyword` fails with the Lua config backend (configType = "lua"), so
    // use `hyprctl eval` with the same table shape as hyprland.nix's static setting.
    function syncHyprlandBorders() {
        const from = root.hyprHex(root.color.hyprBorderActiveFrom);
        const to = root.hyprHex(root.color.hyprBorderActiveTo);
        const inactive = root.hyprHex(root.color.hyprBorderInactive);
        // Always two stops (flat themes set both equal) to match hyprland.nix's shape.
        const activeExpr = `hl.config({general = {["col.active_border"] = {colors = {"rgba(${from})", "rgba(${to})"}, angle = 45}}})`;
        const inactiveExpr = `hl.config({general = {["col.inactive_border"] = "rgba(${inactive})"}})`;
        Quickshell.execDetached(["hyprctl", "eval", activeExpr]);
        Quickshell.execDetached(["hyprctl", "eval", inactiveExpr]);
    }

    // Live-syncs Ghostty via a config-file include (ghostty.nix: `config-file =
    // "?~/.local/state/quickshell-ghostty-theme.conf"`); included directives apply
    // after the including file, so this wins over stylix. Uses raw base16 with the
    // standard ANSI mapping since a terminal needs all 16 slots. New windows pick it
    // up; the reload-config D-Bus call for open windows is best-effort only.
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

    // Live-syncs Zed's chrome colors (not syntax colors), using stylix's generated
    // ~/.config/zed/themes/stylix.json as a template. zed.nix's
    // `theme = "Quickshell Live"` points at the output file.
    property var zedTemplate: null

    FileView {
        id: zedTemplateFile
        path: `${Quickshell.env("HOME")}/.config/zed/themes/stylix.json`
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                root.zedTemplate = JSON.parse(text());
            } catch (e) {
                console.warn(`Theme: failed to parse zed stylix.json template: ${e}`);
            }
            root.syncZedTheme();
        }
    }

    function zedChromeStyle(b16) {
        const hex = (base, alpha) => `#${base}${alpha ?? "ff"}`;
        return {
            "background": hex(b16.base00),
            "border": hex(b16.base02),
            "border.variant": hex(b16.base01),
            "border.focused": hex(b16.base0D),
            "border.selected": hex(b16.base02),
            "border.disabled": hex(b16.base03),
            "elevated_surface.background": hex(b16.base01),
            "surface.background": hex(b16.base01),
            "element.background": hex(b16.base01),
            "element.hover": hex(b16.base02),
            "element.active": hex(b16.base02),
            "element.selected": hex(b16.base02),
            "element.disabled": hex(b16.base01),
            "ghost_element.hover": hex(b16.base02),
            "ghost_element.active": hex(b16.base02),
            "ghost_element.selected": hex(b16.base02),
            "ghost_element.disabled": hex(b16.base01),
            "text": hex(b16.base05),
            "text.muted": hex(b16.base04),
            "text.placeholder": hex(b16.base03),
            "text.disabled": hex(b16.base03),
            "text.accent": hex(b16.base0D),
            "status_bar.background": hex(b16.base01),
            "title_bar.background": hex(b16.base01),
            "title_bar.inactive_background": hex(b16.base00),
            "toolbar.background": hex(b16.base00),
            "tab_bar.background": hex(b16.base01),
            "tab.inactive_background": hex(b16.base01),
            "tab.active_background": hex(b16.base00),
            "panel.background": hex(b16.base01),
            "editor.background": hex(b16.base00),
            "editor.foreground": hex(b16.base05),
            "editor.gutter.background": hex(b16.base00),
            "editor.subheader.background": hex(b16.base01),
            "editor.active_line.background": hex(b16.base01, "80"),
            "editor.highlighted_line.background": hex(b16.base01),
            "editor.line_number": hex(b16.base03),
            "editor.active_line_number": hex(b16.base05),
            "editor.hover_line_number": hex(b16.base04),
            "editor.invisible": hex(b16.base03),
            "terminal.background": hex(b16.base00),
            "terminal.foreground": hex(b16.base05),
            "terminal.bright_foreground": hex(b16.base07),
            "terminal.dim_foreground": hex(b16.base03),
            "terminal.ansi.black": hex(b16.base00),
            "terminal.ansi.bright_black": hex(b16.base03),
            "terminal.ansi.dim_black": hex(b16.base00),
            "terminal.ansi.white": hex(b16.base05),
            "terminal.ansi.bright_white": hex(b16.base07),
            "terminal.ansi.dim_white": hex(b16.base04),
            "terminal.ansi.red": hex(b16.base08),
            "terminal.ansi.bright_red": hex(b16.base08),
            "terminal.ansi.dim_red": hex(b16.base08, "bf"),
            "terminal.ansi.green": hex(b16.base0B),
            "terminal.ansi.bright_green": hex(b16.base0B),
            "terminal.ansi.dim_green": hex(b16.base0B, "bf"),
            "terminal.ansi.yellow": hex(b16.base0A),
            "terminal.ansi.bright_yellow": hex(b16.base0A),
            "terminal.ansi.dim_yellow": hex(b16.base0A, "bf"),
            "terminal.ansi.blue": hex(b16.base0D),
            "terminal.ansi.bright_blue": hex(b16.base0D),
            "terminal.ansi.dim_blue": hex(b16.base0D, "bf"),
            "terminal.ansi.magenta": hex(b16.base0E),
            "terminal.ansi.bright_magenta": hex(b16.base0E),
            "terminal.ansi.dim_magenta": hex(b16.base0E, "bf"),
            "terminal.ansi.cyan": hex(b16.base0C),
            "terminal.ansi.bright_cyan": hex(b16.base0C),
            "terminal.ansi.dim_cyan": hex(b16.base0C, "bf")
        };
    }

    function syncZedTheme() {
        if (!root.zedTemplate || !root.base16 || !root.base16.base00)
            return;
        const obj = JSON.parse(JSON.stringify(root.zedTemplate));
        obj.name = "Quickshell Live";
        obj.themes[0].name = "Quickshell Live";
        Object.assign(obj.themes[0].style, root.zedChromeStyle(root.base16));
        zedFile.setText(JSON.stringify(obj, null, 2));
    }

    FileView {
        id: zedFile
        path: `${Quickshell.env("HOME")}/.config/zed/themes/quickshell-live.json`
        watchChanges: false
        printErrors: false
    }

    // The greeter's system user can't read $HOME (keep it 0700), so the current
    // wallpaper is copied into this user-owned share (tmpfiles in greetd.nix).
    // Read side: desktop/greeter/modules/greeter/Wallpaper.qml.
    readonly property string greeterShareDir: "/var/lib/quickshell-greeter"

    // "scene" and "shader" fall back to the theme's gif, then image; porting the
    // scene renderer into the pre-login boundary isn't worth it.
    function greeterWallpaperFile() {
        const w = root.wallpaper;
        if (!w)
            return null;
        if (w.engine === "gif")
            return { file: w.gif, isGif: true };
        if (w.engine === "static")
            return { file: w.image, isGif: false };
        if (w.gif)
            return { file: w.gif, isGif: true };
        if (w.image)
            return { file: w.image, isGif: false };
        return null;
    }

    function syncGreeterWallpaper() {
        const w = root.wallpaper;
        const resolved = root.greeterWallpaperFile();
        if (!w || !resolved || !resolved.file)
            return;
        const src = `${w.dir}/${resolved.file}`;
        const destName = resolved.isGif ? "current.gif" : "current.png";
        const dest = `${root.greeterShareDir}/${destName}`;
        const stale = resolved.isGif ? "current.png" : "current.gif";
        // Remove the other extension so a static<->gif switch leaves no stale file.
        Quickshell.execDetached(["bash", "-c", `rm -f '${root.greeterShareDir}/${stale}' && cp -f '${src}' '${dest}' && chmod 640 '${dest}'`]);
        greeterWallpaperMeta.setText(JSON.stringify({ file: destName, isGif: resolved.isGif }));
    }

    FileView {
        id: greeterWallpaperMeta
        path: `${root.greeterShareDir}/wallpaper.json`
        watchChanges: false
        printErrors: false
    }

    onColorChanged: {
        root.syncHyprlandBorders();
        root.syncGhosttyTheme();
        root.syncZedTheme();
    }
    // Separate from onColorChanged: a wallpaper override can change without the theme.
    onWallpaperChanged: root.syncGreeterWallpaper()
    Component.onCompleted: {
        root.syncHyprlandBorders();
        root.syncGhosttyTheme();
        root.syncZedTheme();
        root.syncGreeterWallpaper();
    }
}
