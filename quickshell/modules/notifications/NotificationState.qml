pragma Singleton
import QtQuick

// DND state and notification history, both in-memory only for this pass —
// FileView's write-side API wasn't independently confirmed this session,
// so persistence across a Quickshell restart is deferred rather than
// guessed at; both reset on restart until that's verified and wired up.
//
// History is a plain snapshot array, NOT the live `trackedNotifications`
// model Toast.qml renders -- that model only holds currently-undismissed
// notifications (an item leaves it the moment it's dismissed/expired), so
// a genuine history needs its own capture at arrival time. NotifierServer's
// onNotification is where each entry gets pushed in (see that file).
QtObject {
    id: root

    property bool dnd: false

    function toggleDnd() {
        dnd = !dnd;
    }

    readonly property int maxHistory: 50
    property var history: [] // [{summary, body, appName, urgency, timestamp}]

    function recordNotification(notification) {
        const entry = {
            summary: notification.summary ?? "",
            body: notification.body ?? "",
            appName: notification.appName ?? "",
            urgency: notification.urgency,
            timestamp: Date.now()
        };
        root.history = [entry, ...root.history].slice(0, root.maxHistory);
    }

    function clearHistory() {
        root.history = [];
    }

    // Ids of live notifications whose toast has been put away (they wait on
    // an answer, so they stay open in the Notification Centre instead of
    // expiring). Replaced, not mutated, so bindings re-evaluate.
    property var hiddenToasts: ({})

    function hideToast(id) {
        const next = Object.assign({}, root.hiddenToasts);
        next[id] = true;
        root.hiddenToasts = next;
    }

    function isToastHidden(id) {
        return root.hiddenToasts[id] === true;
    }

    function forgetToast(id) {
        if (!(id in root.hiddenToasts))
            return;
        const next = Object.assign({}, root.hiddenToasts);
        delete next[id];
        root.hiddenToasts = next;
    }
}
