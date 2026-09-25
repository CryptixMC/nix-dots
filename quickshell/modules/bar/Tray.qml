import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../theme"

// System tray module (icon-size 15). Structurally a dynamic Repeater over
// SystemTray.items rather than a single BarIcon. Right-click renders the
// item's DBusMenu via TrayMenu.qml's own themed popup rather than calling
// SystemTrayItem.display() -- that method opens a native QPlatformMenu,
// which silently no-ops (logged: "not started in QApplication mode")
// unless the shell runs with `pragma UseQApplication`, which this one
// doesn't.
Row {
    id: root

    // This is the gap *between tray icons themselves*, distinct from
    // (and not the same value as) the top-level modules-right spacing
    // in RightModules.qml.
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
