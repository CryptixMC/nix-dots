import QtQuick 2.15
import QtQml 2.15
import Quickshell
import Quickshell.Io
import "modules/bar"
import "modules/notifications"
import "modules/launcher"
import "modules/qubi/qml"
import "theme"
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

    // Everything Qubi (chat, compare, sessions, model browser, extensions,
    // clipboard, ask-user, screen context, voice, notes) is one component
    // from its own tree -- modules/qubi/ is the qubi repo, see its README.
    // It imports nothing from this shell; `theme` is the whole interface,
    // and themes/<name>/theme.json can override Qubi's tokens under a
    // `qubi` key. Its IPC targets are bound in hyprland.nix.
    Qubi {
        theme: Theme
        config: ({
            defaultCwd: `${Quickshell.env("HOME")}/nix-dots`,
            hwStateFile: "/run/ai-workstation/state.json"
        })
    }

    // Deliberately no keybind — LockService (modules/lock/) is complete
    // but untested against a real Wayland session; the only trigger is
    // this manual IPC call (`quickshell ipc call lock lock`), run by hand
    // once someone's ready to verify the unlock path works
    // before wiring in a real keybind/idle-timeout. See TODO.md §5.
    IpcHandler {
        target: "lock"
        function lock(): void {
            LockService.lock();
        }
    }

    // Two SEPARATE Variants blocks, deliberately — `Variants.delegate` is
    // its default property and is a single QQmlComponent pointer, NOT a
    // list (confirmed against quickshell-core.qmltypes). Putting Wallpaper
    // and Bar inside one Variants silently makes the second overwrite the
    // first, with no warning and a clean config load: that is exactly how
    // the wallpaper disappeared (Hyprland's background layer was empty
    // while the bar rendered fine). Never merge these two blocks.
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