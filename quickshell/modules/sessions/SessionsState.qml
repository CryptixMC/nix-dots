pragma Singleton
import QtQuick

// Show/hide state + the fetched session list for the session-history
// picker. Kept minimal — the list is refetched fresh from GooseAcpSession's
// real ACP session/list every time the picker opens (session metadata is
// cheap to refetch and can change between opens), not cached/persisted
// here.
QtObject {
    id: root

    property bool visible: false
    property var sessions: []
    property bool loading: false

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}
