import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../theme"
import "../wallpaper"

// Content of each per-screen WlSessionLockSurface (a plain Item, not a window).
// No Escape handler: the lock must only close on successful auth.
// Not wired to a trigger yet, see LockService.qml (TODO.md §5).
Item {
    id: root

    required property var lockSurface

    anchors.fill: parent

    WallpaperContent {
        anchors.fill: parent
        wp: Theme.wallpaper
        shouldAnimate: true
        // The scene HUD would overlap this file's left column.
        showSceneHud: false
    }

    // Uptime is read once and advanced by wall-clock deltas; /proc/uptime
    // can't be relied on to signal changes.
    property string hostname: ""
    property real uptimeBaseSeconds: 0
    property real uptimeBaseMs: 0
    property string uptimeText: "T+ 00:00:00"

    function formatUptime(totalSeconds) {
        const s = Math.max(0, Math.floor(totalSeconds));
        const pad = n => String(n).padStart(2, "0");
        return `T+ ${pad(Math.floor(s / 3600))}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}`;
    }

    FileView {
        path: "/etc/hostname"
        onLoaded: root.hostname = text().trim().toUpperCase()
        printErrors: false
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: {
            const secs = parseFloat(text().split(" ")[0]);
            if (!isNaN(secs)) {
                root.uptimeBaseSeconds = secs;
                root.uptimeBaseMs = Date.now();
                root.uptimeText = root.formatUptime(secs);
            }
        }
        printErrors: false
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.uptimeText = root.formatUptime(root.uptimeBaseSeconds + (Date.now() - root.uptimeBaseMs) / 1000)
    }

    Column {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: 96
        }
        spacing: 10

        Text {
            text: Qt.formatDateTime(new Date(), "h:mm")
            color: Theme.color.textStrong
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeDisplay
            font.bold: true

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: parent.text = Qt.formatDateTime(new Date(), "h:mm")
            }
        }

        Row {
            spacing: 24

            Row {
                spacing: 8
                Text {
                    text: "UPTIME"
                    color: Theme.color.textDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }
                Text {
                    text: root.uptimeText
                    color: Theme.color.textLabel
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }
            }

            Row {
                spacing: 8
                Text {
                    text: "HOST"
                    color: Theme.color.textDim
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }
                Text {
                    text: root.hostname.length > 0 ? `[ ${root.hostname} ]` : ""
                    color: Theme.color.textLabel
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }
            }
        }

        Item { width: 1; height: 16 } // gap before the field

        Text {
            // PAM's prompt once a conversation starts, else a static label.
            text: LockService.phase === LockService.phaseFailed ? LockService.errorMessage : (LockService.prompt.length > 0 ? LockService.prompt : "Password:")
            // Failure is shown by colour only, no shake.
            color: LockService.phase === LockService.phaseFailed ? Theme.color.critical : Theme.color.textBody
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
        }

        Rectangle {
            width: Theme.spacing.launcherWidth
            height: Theme.spacing.launcherInputHeight
            radius: Theme.radius.input
            color: Theme.color.ground
            border.width: (passwordInput.activeFocus || LockService.phase === LockService.phaseFailed) ? Theme.spacing.borderCard : Theme.spacing.borderHairline
            border.color: LockService.phase === LockService.phaseFailed ? Theme.color.critical : (passwordInput.activeFocus ? Theme.color.focus : Theme.color.line)

            Text {
                // nf-fa-lock (U+F023)
                text: ""
                anchors {
                    left: parent.left
                    leftMargin: Theme.spacing.launcherRowInset
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.color.textBody
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                renderType: Text.NativeRendering
            }

            TextInput {
                id: passwordInput
                anchors {
                    left: parent.left
                    right: retHint.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: Theme.spacing.launcherRowInset + Theme.spacing.launcherIconLabelGap + 12
                    rightMargin: 8
                }
                enabled: LockService.phase === LockService.phasePrompting
                echoMode: LockService.maskInput ? TextInput.Password : TextInput.Normal
                color: Theme.color.textStrong
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase

                onAccepted: {
                    LockService.submit(text);
                    text = "";
                }
            }

            // Static "Ret" key hint, not interactive.
            Text {
                id: retHint
                text: "Ret"
                anchors {
                    right: parent.right
                    rightMargin: Theme.spacing.launcherRowInset
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.color.textDim
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }
    }

    Component.onCompleted: passwordInput.forceActiveFocus()
}
