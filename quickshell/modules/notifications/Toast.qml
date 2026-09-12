import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../../theme"

// Toast popups for the notification daemon (see NotificationServer.qml).
// Rendered on Quickshell.screens[0] only — not per-Variants-delegate, so a
// multi-monitor setup doesn't pop the same toast on every screen.
PanelWindow {
    id: root

    property var server: null
    // Repeater.count is reliable regardless of the exact underlying model
    // type Notifications exposes — a hand-rolled `.values.length` read on
    // `trackedNotifications` silently stayed 0 (never threw, never
    // updated), which meant `visible` below never went true even though
    // notifications were arriving. Exposed so the bar icon (a separate
    // window, can't reach this file's local Repeater) can read it too.
    readonly property alias activeCount: notifRepeater.count

    screen: Quickshell.screens[0] ?? null
    visible: server !== null && activeCount > 0

    anchors {
        top: true
        right: true
    }
    exclusiveZone: 0
    // Overlay (not the bar's default Top) so toasts render above a
    // fullscreen window — `layer` is not a plain PanelWindow property,
    // it's WlrLayershell's attached property.
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    implicitWidth: Theme.spacing.toastWidth
    implicitHeight: list.implicitHeight + Theme.spacing.toastWindowPadY

    Column {
        id: list
        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.spacing.toastWindowInset
        }
        spacing: Theme.spacing.toastGap
        width: Theme.spacing.toastListWidth

        Repeater {
            id: notifRepeater
            model: root.server ? root.server.trackedNotifications : null

            Rectangle {
                id: card
                required property var modelData

                width: list.width
                implicitHeight: column.implicitHeight + Theme.spacing.toastCardPadY
                radius: Theme.radius.popup
                color: Theme.color.tooltipBg
                border.width: Theme.spacing.borderCard
                border.color: card.modelData.urgency === NotificationUrgency.Critical ? Theme.color.accentPink : Theme.color.tooltipBorder

                Column {
                    id: column
                    anchors {
                        left: parent.left
                        top: parent.top
                        leftMargin: Theme.spacing.toastCardInset
                        topMargin: Theme.spacing.toastCardInset
                        rightMargin: Theme.spacing.toastCardInset + Theme.spacing.toastCloseSize + Theme.spacing.toastLineGap
                    }
                    width: parent.width - anchors.leftMargin - anchors.rightMargin
                    spacing: Theme.spacing.toastLineGap

                    Text {
                        width: parent.width
                        text: card.modelData.summary
                        color: Theme.color.tooltipFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        font.bold: Theme.font.weightBold
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: card.modelData.body.length > 0
                        width: parent.width
                        text: card.modelData.body
                        color: Theme.color.tooltipMuted
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        wrapMode: Text.Wrap
                    }
                }

                Text {
                    id: closeButton
                    text: "✕"
                    anchors {
                        top: parent.top
                        right: parent.right
                        margins: Theme.spacing.toastCardInset
                    }
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    color: closeArea.containsMouse ? Theme.color.tooltipFg : Theme.color.tooltipMuted

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.modelData.dismiss()
                    }
                }

                // expireTimeout follows the freedesktop notification spec:
                // 0 means "never auto-expire" (dismiss stays manual-only),
                // -1 means "no timeout specified, daemon picks" — the most
                // common value in the wild, and the one the old `> 0` check
                // silently dropped, leaving toasts stuck forever with no
                // way to close them.
                Timer {
                    running: card.modelData.expireTimeout !== 0
                    interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout : Theme.motion.toastTimeoutMs
                    onTriggered: card.modelData.expire()
                }
            }
        }
    }
}
