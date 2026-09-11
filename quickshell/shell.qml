import QtQuick
import QtQml
import Quickshell
import "modules/bar"
import "modules/notifications"
import "modules/launcher"
import "modules/wallpaper"

ShellRoot {
    // One-line kill-switch: NotificationServer claims
    // org.freedesktop.Notifications the moment it's instantiated (no
    // lazy-claim flag exists) — flip this to false if a standalone daemon
    // (mako/dunst/swaync) is ever added instead, to avoid a silent D-Bus
    // name race between the two.
    readonly property bool enableNotificationDaemon: true

    Loader {
        id: notifierLoader
        active: enableNotificationDaemon
        sourceComponent: Component {
            NotifierServer {}
        }
    }

    Toast {
        id: toast
        server: notifierLoader.item
    }

    Launcher {
        id: launcher
    }

    Variants {
        model: Quickshell.screens

        Wallpaper {
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        Bar {
            screen: modelData
            notifServer: notifierLoader.item
            notifActiveCount: toast.activeCount
        }
    }
}
