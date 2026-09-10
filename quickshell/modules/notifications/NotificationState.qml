pragma Singleton
import QtQuick

// DND state, in-memory only for this pass — FileView's write-side API
// wasn't independently confirmed this session, so persistence across a
// Quickshell restart is deferred rather than guessed at; resets to false
// on restart until that's verified and wired up.
QtObject {
    property bool dnd: false

    function toggleDnd() {
        dnd = !dnd;
    }
}
