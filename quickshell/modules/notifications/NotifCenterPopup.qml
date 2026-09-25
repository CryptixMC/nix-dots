import QtQuick
import Quickshell
import "../../theme"

// Notification history + DND toggle. Same VolumePopup-derived template as
// every other bar flyout; the one addition is a ListView instead of a
// fixed-height Column, since history can genuinely run to dozens of
// entries and a fixed layout would either clip or balloon the popup.
PopupWindow {
    id: root

    property var anchorItem: null
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: Theme.spacing.notifCenterWidth
    implicitHeight: Math.min(Theme.spacing.notifCenterMaxHeight, content.implicitHeight + Theme.spacing.notifCenterPad * 2)

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: if (!hover.hovered)
            root.visible = false
    }
    onVisibleChanged: if (visible)
        closeTimer.stop()

    Rectangle {
        anchors.fill: parent
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.notifCenterPad
            }
            topPadding: Theme.spacing.notifCenterPad
            spacing: Theme.spacing.notifCenterGap

            Row {
                width: parent.width

                Text {
                    width: parent.width - 130
                    text: "NOTIFICATIONS"
                    color: Theme.color.accentPurple
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }

                Row {
                    spacing: 10

                    Text {
                        text: NotificationState.dnd ? "\u{F009B}" : "\u{F009C}" // md-bell_off / md-bell_outline
                        renderType: Text.NativeRendering
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        color: NotificationState.dnd ? Theme.color.accentPink : Theme.color.rightModuleFg
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: NotificationState.toggleDnd() }
                    }
                    Text {
                        visible: NotificationState.history.length > 0
                        text: "\u{F05E9}" // md-delete_sweep
                        renderType: Text.NativeRendering
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        color: Theme.color.rightModuleFg
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: NotificationState.clearHistory() }
                    }
                }
            }

            Text {
                visible: NotificationState.history.length === 0
                width: parent.width
                text: "no notifications yet"
                color: Theme.color.tooltipMuted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            ListView {
                width: parent.width
                height: Math.min(Theme.spacing.notifCenterMaxHeight - 80, contentHeight)
                visible: NotificationState.history.length > 0
                clip: true
                spacing: Theme.spacing.notifCenterGap
                model: NotificationState.history

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: ListView.view.width
                    height: cardColumn.implicitHeight + Theme.spacing.notifCenterCardPad * 2
                    radius: Theme.radius.input
                    color: ThemeDefaults.alpha(Theme.base16.base02, 0.4)

                    Column {
                        id: cardColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: Theme.spacing.notifCenterCardPad
                        }
                        spacing: 2

                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - 60
                                elide: Text.ElideRight
                                text: card.modelData.summary
                                color: Theme.color.tooltipFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                                font.bold: true
                            }
                            Text {
                                width: 60
                                horizontalAlignment: Text.AlignRight
                                text: {
                                    const mins = Math.floor((Date.now() - card.modelData.timestamp) / 60000);
                                    if (mins < 1)
                                        return "now";
                                    if (mins < 60)
                                        return `${mins}m`;
                                    return `${Math.floor(mins / 60)}h`;
                                }
                                color: Theme.color.tooltipMuted
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                        Text {
                            visible: card.modelData.body.length > 0
                            width: parent.width
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: card.modelData.body
                            color: Theme.color.tooltipMuted
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                        Text {
                            visible: card.modelData.appName.length > 0
                            text: card.modelData.appName
                            color: Theme.color.tooltipMuted
                            font.family: Theme.font.family
                            font.pixelSize: 9
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.spacing.notifCenterPad }
        }
    }
}
