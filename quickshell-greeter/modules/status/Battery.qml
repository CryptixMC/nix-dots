import QtQuick
import Quickshell.Services.UPower
import "../../theme"

// Trimmed adaptation of quickshell/modules/bar/Battery.qml — same UPower
// binding and icon-tier logic, no tooltip (cage has no wlr-layer-shell, so
// the bar's PopupWindow-based ModuleTooltip isn't usable here at all; a
// plain inline percentage label covers the same information at a glance).
Row {
    id: root
    spacing: 6
    visible: device !== null

    readonly property var device: UPower.displayDevice
    readonly property real percentage: (device?.percentage ?? 0) * 100
    readonly property var dischargeIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: {
            if (!root.device)
                return "󰁹";
            if (root.device.state === UPowerDeviceState.FullyCharged)
                return "󰁹";
            if (root.device.state === UPowerDeviceState.Charging || root.device.state === UPowerDeviceState.PendingCharge)
                return "󰂄";
            if (!UPower.onBattery)
                return "󰚥";
            return root.dischargeIcons[Math.min(9, Math.floor(root.percentage / 10))];
        }
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${Math.round(root.percentage)}%`
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
