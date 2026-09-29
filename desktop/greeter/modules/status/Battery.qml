import QtQuick
import Quickshell.Services.UPower
import "../../theme"

// Battery status with an inline percentage; no tooltip since cage has no
// layer shell for PopupWindow.
Row {
    id: root
    spacing: 6
    visible: device !== null

    readonly property var device: UPower.displayDevice
    readonly property real percentage: (device?.percentage ?? 0) * 100
    readonly property var dischargeIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    // Critical is colour-only, no blink.
    readonly property bool isCritical: percentage <= 15 && device?.state === UPowerDeviceState.Discharging
    readonly property color tint: root.isCritical ? Colors.errorRed : Colors.textBody

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
        color: root.tint
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${Math.round(root.percentage)}%`
        color: root.tint
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
