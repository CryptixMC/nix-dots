import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../../theme"

// Click-to-open Bluetooth device flyout, same upgrade pattern as
// VolumePopup.qml/NetworkPopup.qml — replaces launching blueman-manager
// directly on click. Lists already-known/paired devices (adapter.devices)
// with click-to-connect/disconnect; pairing a genuinely new device needs
// proper scan/pairing UX this API doesn't cleanly expose (BluetoothAdapter
// has no direct startDiscovery method, only a read-only `discovering`
// status), so blueman-manager stays the escape hatch for that case rather
// than a half-built pairing flow here.
PopupWindow {
    id: root

    property var anchorItem: null
    property var adapter: null

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    readonly property var devices: adapter ? adapter.devices.values.slice().sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0)) : []

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: Theme.spacing.launcherWidth
    implicitHeight: content.implicitHeight + Theme.spacing.launcherContentInset * 2

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 800
        onTriggered: if (!hover.hovered)
            root.visible = false
    }

    onVisibleChanged: if (visible)
        closeTimer.stop()

    function activate(dev) {
        if (dev.connected)
            dev.disconnect();
        else if (dev.paired || dev.bonded)
            dev.connect();
        else
            dev.pair();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap / 2

            Text {
                text: "BLUETOOTH"
                color: Theme.color.tooltipMuted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                visible: root.devices.length === 0
                text: "no known devices — use blueman to pair one"
                color: Theme.color.tooltipMuted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Repeater {
                model: root.devices

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: content.width
                    height: Theme.spacing.launcherRowHeight
                    radius: Theme.radius.input
                    color: modelData.connected ? Theme.color.launcherItemSelectedBg : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacing.launcherRowInset
                            rightMargin: Theme.spacing.launcherRowInset
                        }
                        spacing: Theme.spacing.volumePopupGap

                        Text {
                            text: row.modelData.connected ? "󰂱" : "󰂲"
                            color: row.modelData.connected ? Theme.color.accentPurple : Theme.color.rightModuleFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width - (row.modelData.batteryAvailable ? 100 : 40)
                            text: row.modelData.deviceName
                            elide: Text.ElideRight
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                        }

                        Text {
                            visible: row.modelData.batteryAvailable
                            text: Math.round(row.modelData.battery * 100) + "%"
                            color: Theme.color.tooltipMuted
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activate(row.modelData)
                    }
                }
            }

            Text {
                text: "› pair new device (blueman)"
                color: Theme.color.rightModuleFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["blueman-manager"]);
                        root.visible = false;
                    }
                }
            }
        }
    }
}
