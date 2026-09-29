import Quickshell.Services.Notifications

// Named NotifierServer to avoid shadowing the imported type. Creating it claims
// org.freedesktop.Notifications, so it lives behind shell.qml's Loader;
// never make it a singleton (lazy creation would bypass that kill-switch).
NotificationServer {
    bodySupported: true
    actionsSupported: true
    imageSupported: true
    persistenceSupported: false
    inlineReplySupported: true

    // Notifications must be opted into tracking explicitly or
    // trackedNotifications stays empty. History is captured here because
    // tracked entries vanish once dismissed.
    onNotification: notification => {
        notification.tracked = true;
        NotificationState.recordNotification(notification);
        const id = notification.id;
        notification.closed.connect(() => NotificationState.forgetToast(id));
    }
}
