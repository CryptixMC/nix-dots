import Quickshell.Services.Notifications

// Thin config wrapper around Quickshell's NotificationServer — named
// NotifierServer (not NotificationServer) to avoid shadowing the imported
// type of the same name within this very file's own root declaration.
// Instantiated exactly once, behind a Loader in shell.qml gated by
// `enableNotificationDaemon`, since instantiation itself claims
// org.freedesktop.Notifications on the session bus with no lazy-claim flag
// available. Never make this a singleton: singletons are lazily created on
// first property access from anywhere, which would defeat the explicit
// kill-switch this needs.
NotificationServer {
    bodySupported: true
    actionsSupported: true
    imageSupported: true
    persistenceSupported: false
    inlineReplySupported: true

    // trackedNotifications stayed permanently empty without this — the
    // server doesn't auto-retain incoming notifications, each one must be
    // explicitly opted into tracking via this signal (confirmed empirically:
    // Notify() succeeded and returned an ID, but nothing landed in
    // trackedNotifications until this was added).
    //
    // recordNotification() also snapshots into NotificationState.history --
    // trackedNotifications itself isn't a history (an entry leaves it the
    // moment it's dismissed/expired), so the Notification Centre's history
    // list needs its own capture taken right here, at arrival time.
    onNotification: notification => {
        notification.tracked = true;
        NotificationState.recordNotification(notification);
    }
}
