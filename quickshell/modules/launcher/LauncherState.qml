pragma Singleton
import QtQuick

// Global show/hide state, reachable from Launcher.qml's IpcHandler
// (external `quickshell ipc call` from a Hyprland keybind) and from the
// window itself. Search text deliberately isn't mirrored here — it lives
// as local state on Launcher.qml's TextInput and gets reset in that file's
// onVisibleChanged, since a two-way binding between a TextInput's `text`
// and a singleton property tears the moment the user types (TextInput sets
// `text` imperatively, which permanently breaks a declarative `text: ...`
// binding on the same property).
QtObject {
    property bool visible: false

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}
