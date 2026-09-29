pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Active theme name, persistence and IPC switching. Item root because it needs
// both a FileView and an IpcHandler child (FileView holds only one).
Item {
    id: root

    readonly property string defaultTheme: "ultraviolet"
    readonly property string activeThemeName: persistence.adapter.activeTheme || root.defaultTheme

    // Seeding is deferred to the first write: setText() inside onLoadFailed hits a
    // FileView reentrancy bug (same as UsageStore.qml).
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

    // Per-theme wallpaper override from the Themes tab; Theme.qml resolves it
    // before the theme.json default.
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

    // "Slight transparency" for menu surfaces, applied centrally in Theme.qml.
    readonly property bool menuTranslucent: persistence.adapter.menuTranslucent ?? false

    function setMenuTranslucent(v) {
        if (root.needsSeed) {
            persistence.setText(JSON.stringify({
                activeTheme: root.defaultTheme,
                wallpaperOverrides: {},
                menuTranslucent: false
            }));
            root.needsSeed = false;
        }
        persistence.adapter.menuTranslucent = v;
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
            property bool menuTranslucent: false
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
