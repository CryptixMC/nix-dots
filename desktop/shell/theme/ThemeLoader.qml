pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

// Discovers themes/*/ folders and loads each via ThemeEntryLoader. Discovery
// runs once at startup; rescan() is an unused hook for a future IPC call.
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
