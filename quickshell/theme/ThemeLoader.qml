pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

// Discovers themes/*/ folders at startup and loads each one via a
// ThemeEntryLoader. Runtime-only (Process + FileView), no Nix build step —
// quickshell/ isn't Nix-packaged, it runs from a live repo checkout, and
// this stays consistent with that.
//
// v1 limitation: discovery runs once, at startup. A brand-new themes/<name>/
// folder needs a Quickshell restart to be picked up (FileView watches
// files, not directory contents) — rescan() exists as a hook for wiring a
// live "theme rescan" IPC function later, not called from anywhere yet.
Item {
    id: root

    readonly property string themesDir: `${Quickshell.shellDir}/../themes`
    property var discoveredThemeNames: []
    property var themes: ({})

    function mergeEntry(name, data) {
        const next = Object.assign({}, root.themes);
        next[name] = data;
        root.themes = next;
    }

    function rescan() {
        discovery.running = true;
    }

    Process {
        id: discovery
        running: true
        command: ["find", root.themesDir, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-printf", "%f\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.discoveredThemeNames = text.split("\n").filter(n => n.length > 0);
            }
        }
    }

    Instantiator {
        model: root.discoveredThemeNames
        delegate: ThemeEntryLoader {
            required property string modelData
            themeName: modelData
            themesDir: root.themesDir
            onLoaded: (name, data) => root.mergeEntry(name, data)
        }
    }
}
