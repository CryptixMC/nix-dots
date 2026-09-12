pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Active theme name + persistence + live IPC switching. Rooted as a plain
// Item rather than a bare FileView (UsageStore.qml's pattern) because this
// singleton needs two children — a FileView for persistence *and* an
// IpcHandler for live switching — and FileView's default `adapter` property
// is a single pointer, not a list, so it can only ever hold one child
// itself. Item's default `data` property is a list, so both can live here
// as siblings.
Item {
    id: root

    readonly property string defaultTheme: "ultraviolet"
    readonly property string activeThemeName: persistence.adapter.activeTheme || root.defaultTheme

    // First run: no file on disk yet. Deferred to the first actual
    // setTheme() call rather than seeded eagerly in onLoadFailed — see
    // UsageStore.qml's identical needsSeed pattern for why (calling
    // setText() synchronously from inside onLoadFailed hits a FileView
    // operation-queue reentrancy bug).
    property bool needsSeed: false

    function setTheme(name) {
        if (!ThemeLoader.discoveredThemeNames.includes(name)) {
            console.warn(`ThemeState: unknown theme "${name}"`);
            return;
        }
        if (root.needsSeed) {
            persistence.setText(JSON.stringify({
                activeTheme: root.defaultTheme
            }));
            root.needsSeed = false;
        }
        persistence.adapter.activeTheme = name;
        persistence.writeAdapter();
    }

    function cycleTheme() {
        const names = ThemeLoader.discoveredThemeNames;
        root.setTheme(names[(names.indexOf(root.activeThemeName) + 1) % names.length]);
    }

    // Per-theme wallpaper file override, keyed by theme name — set from the
    // launcher's Themes tab wallpaper picker. Theme.qml's `wallpaper` facade
    // resolves this first, falling back to the theme's own theme.json-
    // declared default when no override is set, so themes nobody has
    // touched behave exactly as before this existed.
    readonly property var wallpaperOverrides: persistence.adapter.wallpaperOverrides ?? ({})

    function setWallpaperOverride(themeName, filename) {
        if (root.needsSeed) {
            persistence.setText(JSON.stringify({
                activeTheme: root.defaultTheme,
                wallpaperOverrides: {}
            }));
            root.needsSeed = false;
        }
        const next = Object.assign({}, persistence.adapter.wallpaperOverrides ?? ({}));
        next[themeName] = filename;
        persistence.adapter.wallpaperOverrides = next;
        persistence.writeAdapter();
    }

    FileView {
        id: persistence

        path: `${Quickshell.env("HOME")}/.local/state/quickshell-theme.json`
        watchChanges: false
        printErrors: false
        onLoadFailed: error => root.needsSeed = true

        JsonAdapter {
            property string activeTheme: "ultraviolet"
            property var wallpaperOverrides: ({})
        }
    }

    IpcHandler {
        target: "theme"

        function set(name: string): void {
            root.setTheme(name);
        }
        function next(): void {
            root.cycleTheme();
        }
        function current(): string {
            return root.activeThemeName;
        }
    }
}
