import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../theme"

// Mirrors waybar's "tray" module (icon-size 15). Structurally a dynamic
// Repeater over SystemTray.items rather than a single BarIcon — Quickshell
// renders each item's DBusMenu itself via .display(), no custom menu UI
// needed for a first pass.
Row {
    id: root

    property var barWindow: null

    // waybar.nix's tray.spacing = 10 — this is the gap *between tray
    // icons themselves*, distinct from (and not the same value as) the
    // top-level modules-right spacing in RightModules.qml.
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
                    else if (trayItem.modelData.hasMenu)
                        trayItem.modelData.display(root.barWindow, mouse.x, mouse.y);
                    else
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
        }
    }
}
