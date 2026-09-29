import QtQuick 2.15
import QtQml 2.15
import Quickshell
import Quickshell.Io
import "modules/bar"
import "modules/notifications"
import "modules/launcher"
import Qubi
import "theme"
import "modules/lock"
import "modules/wallpaper"
import "modules/auth"

ShellRoot {
    // NotificationServer claims org.freedesktop.Notifications on creation;
    // set false if a standalone daemon (mako/dunst) is used, to avoid a D-Bus name race.
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


    // Polkit prompt; always mounted so any privileged call can be answered.
    AuthPromptWindow {}

    // Volume/mic/brightness overlay, driven by hardware keys and Quick Settings.
    Osd {}

    // Qubi lives in its own repo and reaches QML_IMPORT_PATH via home-manager;
    // `theme` is its only interface to this shell.
    Qubi {
        theme: Theme
    }

    // Lock is deliberately not bound to a keybind/idle trigger until the unlock
    // path is verified; manual only via `quickshell ipc call lock lock` (TODO.md §5).
    IpcHandler {
        target: "lock"
        function lock(): void {
            LockService.lock();
        }
    }

    // Keep these as two Variants: `delegate` holds a single component, so a
    // second child silently overwrites the first.
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
