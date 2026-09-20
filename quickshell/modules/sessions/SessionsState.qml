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
    property string loadError: ""

    // Most of this history is noise: measured against the real sessions.db,
    // 204 of 365 stored sessions had zero messages -- empty ACP shells
    // created every time the chat panel opened a session it never used. On
    // by default because an empty session is never something you want to
    // resume; the picker exposes a toggle to see them anyway.
    property bool hideEmpty: true

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}
