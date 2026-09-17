pragma Singleton
import QtQuick

// Show/hide state + the parsed extensions list for the extensions/MCP
// manager. config.yaml's extensions: block is re-read fresh every time
// the manager opens (same "refetch, don't cache" discipline as
// SessionsState.qml/ModelBrowserState.qml).
//
// `extensions` holds an array of {key, name, type, enabled, description,
// display_name, cmd} objects derived from config.yaml's extensions
// object (whose own keys are the extension ids) — flattened to an array
// here since QML's ListView/Repeater work naturally over arrays, not
// plain objects.
QtObject {
    id: root

    property bool visible: false
    property var extensions: []
    property bool loading: false

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}
