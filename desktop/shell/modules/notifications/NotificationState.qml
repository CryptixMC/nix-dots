pragma Singleton
import QtQuick

// DND state and notification history, in memory only (reset on restart).
// History is a snapshot array because trackedNotifications drops dismissed items.
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

    // Ids of live notifications whose toast was hidden but which stay open in
    // the Notification Centre. Replaced, not mutated, so bindings re-evaluate.
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
