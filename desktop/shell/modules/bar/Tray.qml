import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../theme"
import "popups"

// System tray. Right-click renders the item's DBusMenu via TrayMenu.qml:
// SystemTrayItem.display() opens a native menu that no-ops unless the
// shell runs with `pragma UseQApplication`, which this one doesn't.
Row {
    id: root

    // Gap between tray icons, distinct from the RightModules spacing.
    spacing: Theme.spacing.trayGap

    Repeater {
        model: SystemTray.items

        Item {
            id: trayItem
            required property var modelData

            width: Theme.spacing.trayIconSize
            height: Theme.spacing.trayIconSize

            IconImage {
                anchors.fill: parent
                source: trayItem.modelData.icon
            }

            MouseArea {
                id: trayMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton)
                        trayItem.modelData.activate();
                    else if (trayItem.modelData.hasMenu) {
                        tooltip.visible = false;
                        hoverTimer.stop();
                        contextMenu.visible = !contextMenu.visible;
                    } else
                        trayItem.modelData.secondaryActivate();
                }
                onWheel: wheel => trayItem.modelData.scroll(wheel.angleDelta.y, false)

                onEntered: hoverTimer.restart()
                onExited: {
                    hoverTimer.stop();
                    tooltip.visible = false;
                }
            }

            Timer {
                id: hoverTimer
                interval: Theme.motion.tooltipHoverDelayMs
                onTriggered: tooltip.visible = true
            }

            ModuleTooltip {
                id: tooltip
                anchor.item: trayItem
                titleText: trayItem.modelData.title || trayItem.modelData.id || ""
                bodyText: trayItem.modelData.tooltipTitle ?? ""
                mutedText: trayItem.modelData.tooltipDescription ?? ""
            }

            TrayMenu {
                id: contextMenu
                anchorItem: trayItem
                menuHandle: trayItem.modelData.menu
            }
        }
    }
}
