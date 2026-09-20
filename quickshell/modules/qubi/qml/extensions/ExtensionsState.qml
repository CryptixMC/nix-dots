pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Show/hide state + the parsed extensions list for the extensions/MCP
// manager, and the source of the chat panel's MCP status indicator.
//
// The config read lives HERE rather than in ExtensionsManager.qml so the
// list is available to any consumer without the manager overlay having
// been opened first -- the chat status bar shows a live enabled-count
// and would otherwise read 0 until the user happened to open the
// manager once.
//
// `extensions` holds an array of {key, name, type, enabled, description,
// display_name, cmd} objects derived from config.yaml's extensions
// object (whose own keys are the extension ids) — flattened to an array
// here since QML's ListView/Repeater work naturally over arrays, not
// plain objects.
// Stays a QtObject (not an Item) specifically because this singleton
// owns a `visible` property: QQuickItem.visible is final, so an Item
// base would shadow it and break every existing consumer. The read
// Process is held as a declared property instead of a visual child.
QtObject {
    id: root

    readonly property string configPath: `${Quickshell.env("HOME")}/.config/goose/config.yaml`

    property bool visible: false
    property var extensions: []
    property bool loading: false

    // What the chat status bar shows: the extensions actually active in a
    // turn, not the full registered roster (24 vs 6 today).
    readonly property int enabledCount: (extensions ?? []).filter(e => e.enabled).length

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }

    function refresh() {
        // Drop overlapping refreshes -- the chat panel and the manager can
        // both ask at once, and a second `yq` mid-flight would just race
        // the first to assign `extensions`.
        if (root.readProcess.running)
            return;
        root.loading = true;
        root.readProcess.running = true;
    }

    // `yq -o=json` rather than `cat` + JSON.parse. config.yaml is real
    // YAML: it is *currently* flow-style (so JSON.parse happens to work),
    // but Goose itself rewrites it in block style after a live `/model`
    // change -- which is exactly what crashed qubi_engine.py with a
    // JSONDecodeError and had to be fixed there with yaml.safe_load.
    // Verified the same way here: `yq -P` the real config to block style
    // and JSON.parse fails on it while this path still resolves all 6
    // enabled extensions. Without this the status bar would silently read
    // "0 MCP" with no visible reason. yq is already a dependency and is
    // already used below for the enable/disable write.
    property Process readProcess: Process {
        command: ["yq", "-o=json", ".", root.configPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    const extObj = parsed.extensions ?? {};
                    root.extensions = Object.keys(extObj).sort().map(key => {
                        const e = extObj[key];
                        return {
                            key: key,
                            name: e.name ?? key,
                            display_name: e.display_name ?? e.name ?? key,
                            type: e.type ?? "",
                            enabled: e.enabled === true,
                            description: e.description ?? "",
                            cmd: e.cmd ?? ""
                        };
                    });
                } catch (e) {
                    root.extensions = [];
                    console.warn("ExtensionsState: failed to parse config.yaml:", e);
                }
                root.loading = false;
            }
        }
    }
}
