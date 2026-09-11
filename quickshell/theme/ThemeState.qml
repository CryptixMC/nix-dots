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

    FileView {
        id: persistence

        path: `${Quickshell.env("HOME")}/.local/state/quickshell-theme.json`
        watchChanges: false
        printErrors: false
        onLoadFailed: error => root.needsSeed = true

        JsonAdapter {
            property string activeTheme: "ultraviolet"
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
