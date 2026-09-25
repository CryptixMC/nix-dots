pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/wallpaper/scenes/registry.js" as SceneRegistry

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

    // False until ThemeLoader's async chain (find -> yq Process -> JSON
    // parse) has actually produced the active theme -- roughly the first
    // 100-300ms of a session or a reload. Until then `current` is
    // `fallback`, which is a genuine ultraviolet-v1 build and therefore
    // uses the BASELINE role mapping: lineStrong resolves to base06, a
    // near-WHITE, where ultraviolet-v2's theme.json remaps it to base0C
    // (purple). Any consumer painting a large area in a role that a
    // theme.json remaps will visibly flash the baseline colour first —
    // the wallpaper scenes gate on this to avoid that (see Orbital.qml).
    // Small UI chrome doesn't bother: a 200ms grey-vs-purple hairline is
    // invisible, a 200ms white globe is not.
    readonly property bool resolved: ThemeLoader.themes[ThemeState.activeThemeName] !== undefined
        || ThemeLoader.themes[ThemeState.defaultTheme] !== undefined

    readonly property var base16: root.current.base16

    // A fixed set of surface-background tokens get alpha-scaled when the
    // user's "slight transparency" toggle (ThemeState.menuTranslucent) is on
    // — applied here rather than in ThemeDefaults.buildColor() so it's one
    // session-preference switch, not baked per-theme-name into the cache.
    readonly property var _translucentBgTokens: ["barBg", "tooltipBg", "launcherBg"]
    readonly property real _menuTranslucentAlphaFactor: 0.75

    function _asRgba(v) {
        // ThemeDefaults.alpha() returns a real Qt.rgba() (.r/.g/.b/.a
        // readable); ThemeDefaults.opaque() returns a bare "#RRGGBB" string
        // with no alpha info. The active theme (ultraviolet-v2) uses the
        // bare-string form for exactly these tokens, so both shapes must
        // resolve to something scalable.
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
    // Every scene in the registry is pickable from every theme's picker —
    // independent of `w`/themeName, unlike `available` below.
    readonly property var availableScenes: SceneRegistry.scenes

    // Resolves a user-picked wallpaper override (Themes tab, via
    // ThemeState.setWallpaperOverride) ahead of the theme's own theme.json-
    // declared default. The override is checked against the scene
    // registry FIRST (a scene name, e.g. "NeuralNet", isn't a file and
    // won't be in `w.available`) — otherwise engine is inferred from the
    // override filename's extension, since a plain image/gif is the only
    // other kind of override ever offered (see ThemeEntryLoader.qml's
    // wallpaper-file discovery) — a shader wallpaper needs a paired
    // uniform set a plain click can't supply, so it's never a candidate.
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

    // Live-syncs Hyprland's own border colors to the active theme via
    // `hyprctl keyword` (applies immediately, no Hyprland restart needed)
    // — the one non-Quickshell surface this theme system also drives live.
    // Reads the dedicated hyprBorder* tokens rather than borrowing UI roles
    // — see ThemeDefaults.buildColor() for why. Their baselines reproduce
    // the previous accentPink/accentPurple/tooltipMuted values exactly, so
    // themes that don't mention them are unaffected.
    //
    // hyprctl wants bare RRGGBBAA. A token here may be either a plain
    // "#RRGGBB" string (opaque() output) or a real Qt color (alpha()
    // output), and Qt stringifies a color with alpha as "#AARRGGBB" — so
    // normalise both shapes and move the alpha pair from front to back.
    // Doing it this way is what lets a token carry its own alpha instead of
    // the hardcoded "aa" suffix this used to append.
    function hyprHex(color) {
        const s = String(color).replace("#", "");
        return s.length === 8 ? s.substring(2) + s.substring(0, 2) : s + "ff";
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
        const from = root.hyprHex(root.color.hyprBorderActiveFrom);
        const to = root.hyprHex(root.color.hyprBorderActiveTo);
        const inactive = root.hyprHex(root.color.hyprBorderInactive);
        // Still a two-stop gradient even when a theme sets both stops to the
        // same colour (ultraviolet-v2 does, to render flat) — keeping the
        // table shape constant means this expression never has to change
        // shape, and it stays identical to hyprland.nix's static setting.
        const activeExpr = `hl.config({general = {["col.active_border"] = {colors = {"rgba(${from})", "rgba(${to})"}, angle = 45}}})`;
        const inactiveExpr = `hl.config({general = {["col.inactive_border"] = "rgba(${inactive})"}})`;
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

    // Live-syncs Zed's chrome colors (not syntax highlighting or player
    // cursor colors — those stay whatever stylix's own build-time "Base16
    // <theme>" theme last generated, a deliberate scope limit to keep this
    // tractable) to the active theme. zed.nix's stylix.targets.zed already
    // produces a full, schema-correct 141-key theme file at
    // ~/.config/zed/themes/stylix.json on every `nh home switch` — reusing
    // that as a structural template (read once, since it only changes on a
    // real rebuild) means this only has to know the ~40 "chrome" keys that
    // should track the *live* theme rather than reimplementing Zed's whole
    // theme schema by hand. zed.nix's `theme = "Quickshell Live"` points at
    // the file this writes.
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

    // Live-syncs a resolved, greeter-safe snapshot of the current wallpaper
    // to /var/lib/quickshell-greeter/ -- the pre-login screen runs as an
    // unprivileged system user with no access into $HOME (0700, and it
    // should stay that way), so it can't read this session's theme state or
    // repo checkout directly. This is the one door between them: cryptix
    // (this session) owns the shared directory (systemd.tmpfiles.rules in
    // greetd.nix) and writes into it; the greeter only ever reads. See
    // quickshell-greeter/modules/greeter/Wallpaper.qml for the read side.
    readonly property string greeterShareDir: "/var/lib/quickshell-greeter"

    // "scene" and "shader" degrade to that theme's own gif-else-image
    // fallback -- the same fallback theme.json already declares for
    // exactly this purpose (every scene/shader wallpaper block ships a
    // `gif` and an `image` alongside `scene`/`shader`, e.g. themes/
    // ultraviolet-v2/theme.json). Porting the actual scene renderer
    // (SystemStats.qml, the whole Orbital tree) into a pre-login security
    // boundary isn't worth it for a few seconds of login screen; an
    // animated GIF of the same plate is the honest next-best thing, which
    // is why this checks `gif` before `image` rather than jumping straight
    // to the static fallback.
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
        // rm the OTHER extension so a static<->gif switch doesn't leave a
        // stale file the sidecar no longer points at, then copy+lock down
        // the new one in one shell-out -- same execDetached-a-real-command
        // style as syncHyprlandBorders()/syncGhosttyTheme() above, not a
        // QML file-copy API (Quickshell doesn't expose one).
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
    // Separate from onColorChanged: a wallpaper override can change
    // (ThemeState.setWallpaperOverride) without the active theme -- and
    // therefore `color` -- changing at all, e.g. picking a different
    // wallpaper file for the theme that's already active.
    onWallpaperChanged: root.syncGreeterWallpaper()
    Component.onCompleted: {
        root.syncHyprlandBorders();
        root.syncGhosttyTheme();
        root.syncZedTheme();
        root.syncGreeterWallpaper();
    }
}
