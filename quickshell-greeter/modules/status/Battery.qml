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
    // Parity gap with the main shell's Battery.qml, which never made it
    // over here: this file had no critical state at all, so a 5% battery
    // rendered identically to a 95% one. Colour-only (no blink) -- matches
    // both the design system's "critical is colour on the thing carrying
    // the problem, nothing else changes" rule and this session's own
    // ruling to drop the blink everywhere else in v2.
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
