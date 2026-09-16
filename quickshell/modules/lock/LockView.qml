import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"

// The lock surface itself — `WlSessionLock.surface` instantiates one of
// these per screen automatically (ext-session-lock-v1 semantics), so this
// stays a plain Item, not a PanelWindow: WlSessionLockSurface is the
// window, this is just its contentItem's root.
//
// v1 background is a flat themed color, not the full Wallpaper.qml engine
// (static/gif/shader dispatch) — that component is tightly coupled to
// being its own PanelWindow at the Background layer, not something to
// re-parent into a lock surface's contentItem for this pass. Omarchy's
// reference does animated backgrounds; deliberately deferred here in favor
// of shipping a working password/fingerprint flow first.
//
// No Escape-to-close handler anywhere in this file — unlike every other
// overlay in this repo (Launcher, Chat, popups), a lock screen must not be
// dismissible without successful authentication.
Item {
    id: root

    required property var lockSurface

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        color: Theme.color.launcherBg
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacing.launcherContentGap

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(new Date(), "h:mm")
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase * 3
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: LockService.phase === LockService.phaseFailed ? LockService.errorMessage : LockService.prompt
            color: LockService.phase === LockService.phaseFailed ? Theme.color.moduleDisabledFg : Theme.color.tooltipMuted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.spacing.launcherWidth
            height: Theme.spacing.launcherInputHeight
            radius: Theme.radius.input
            color: Theme.color.launcherInputBg
            border.width: Theme.spacing.borderHairline
            border.color: LockService.phase === LockService.phaseFailed ? Theme.color.moduleDisabledFg : Theme.color.launcherInputBorder

            TextInput {
                id: passwordInput
                anchors {
                    fill: parent
                    margins: Theme.spacing.launcherInputTextInset
                }
                enabled: LockService.phase === LockService.phasePrompting
                echoMode: LockService.maskInput ? TextInput.Password : TextInput.Normal
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase

                onAccepted: {
                    LockService.submit(text);
                    text = "";
                }
            }
        }
    }

    Component.onCompleted: passwordInput.forceActiveFocus()
}
