import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../../theme"

// Notification toasts, on the first screen only so they don't repeat per monitor.
PanelWindow {
    id: root

    property var server: null
    // Repeater.count updates reliably; trackedNotifications.values.length does not.
    // Exposed for the bar icon.
    readonly property alias activeCount: notifRepeater.count

    screen: Quickshell.screens[0] ?? null
    // A notification can outlive its toast (see the card's Timer), so the
    // window shows only while some card is still visible.
    visible: server !== null && activeCount > 0 && list.implicitHeight > 0

    anchors {
        top: true
        right: true
    }
    exclusiveZone: 0
    // Overlay so toasts render above fullscreen windows.
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand: the toast never grabs the keyboard on its own, but a click
    // into an inline-reply field can take focus so the reply can be typed.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
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

                readonly property var defaultAction: {
                    const all = card.modelData.actions ?? [];
                    for (let i = 0; i < all.length; i++) {
                        if (all[i].identifier === "default")
                            return all[i];
                    }
                    return null;
                }

                // Hidden once its toast time is up, if it still waits on an
                // answer (it stays in the Notification Centre).
                visible: !NotificationState.isToastHidden(card.modelData.id)
                width: list.width
                implicitHeight: column.implicitHeight + Theme.spacing.toastCardPadY
                radius: Theme.radius.popup
                color: Theme.color.tooltipBg
                border.width: Theme.spacing.borderCard
                border.color: card.modelData.urgency === NotificationUrgency.Critical ? Theme.color.accentPink : Theme.color.tooltipBorder

                HoverHandler {
                    id: cardHover
                }

                // A click on the body runs the notification's "default" action
                // (declared first, so the buttons, reply field and close button
                // stay on top of it).
                MouseArea {
                    anchors.fill: parent
                    enabled: card.defaultAction !== null
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: card.defaultAction.invoke()
                }

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

                    ActionButtons {
                        width: parent.width
                        notification: card.modelData
                    }

                    Rectangle {
                        visible: card.modelData.hasInlineReply
                        width: parent.width
                        height: Theme.spacing.launcherInputHeight
                        radius: Theme.radius.input
                        color: Theme.color.launcherInputBg
                        border.width: Theme.spacing.borderHairline
                        border.color: replyInput.activeFocus ? Theme.color.launcherInputBorder : Theme.color.tooltipBorder

                        Text {
                            visible: replyInput.text.length === 0
                            anchors {
                                left: parent.left
                                leftMargin: Theme.spacing.launcherInputTextInset
                                verticalCenter: parent.verticalCenter
                            }
                            text: card.modelData.inlineReplyPlaceholder || "Reply…"
                            color: Theme.color.tooltipMuted
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        TextInput {
                            id: replyInput
                            anchors {
                                fill: parent
                                margins: Theme.spacing.launcherInputTextInset
                            }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.color.tooltipFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            clip: true
                            Keys.onReturnPressed: {
                                if (text.trim().length > 0) {
                                    card.modelData.sendInlineReply(text.trim());
                                    text = "";
                                }
                            }
                        }
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

                // expireTimeout: 0 = never expire, -1 = daemon default. Paused while
                // hovered or replying. Notifications with actions/reply are only
                // hidden, not expired, since expiring closes them for the sender too.
                Timer {
                    running: card.visible && card.modelData.expireTimeout !== 0 && !cardHover.hovered && !replyInput.activeFocus
                    // Quickshell reports expireTimeout in seconds, not the spec's ms.
                    interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000 : Theme.motion.toastTimeoutMs
                    onTriggered: {
                        if ((card.modelData.actions ?? []).length > 0 || card.modelData.hasInlineReply)
                            NotificationState.hideToast(card.modelData.id);
                        else
                            card.modelData.expire();
                    }
                }
            }
        }
    }
}
