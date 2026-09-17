import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import "modules/bar"
import "modules/notifications"
import "modules/launcher"
import "modules/chat"
import "modules/sessions"
import "modules/modelbrowser"
import "modules/extensions"
import "modules/lock"
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

    ChatOverlay {
        id: chatOverlay
    }

    SessionsPicker {
        id: sessionsPicker
    }

    ModelBrowser {
        id: modelBrowser
    }

    ExtensionsManager {
        id: extensionsManager
    }

    // Deliberately no keybind — LockService (modules/lock/) is complete
    // but untested against a real Wayland session; the only trigger is
    // this manual IPC call (`quickshell ipc call lock lock`), run by hand
    // once someone's ready to verify the unlock path actually works
    // before wiring in a real keybind/idle-timeout. See TODO.md §5.
    IpcHandler {
        target: "lock"
        function lock(): void {
            LockService.lock();
        }
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
