import QtQuick
import Quickshell.Services.UPower
import "../../theme"

// Battery module (bat = BAT0). Only critical (<=15%) gets the pink blink;
// there is no separate "warning" tier.
BarIcon {
    id: root

    readonly property var device: UPower.displayDevice
    // UPowerDevice.percentage is a 0.0-1.0 fraction, not 0-100.
    readonly property real percentage: (device?.percentage ?? 0) * 100
    readonly property bool isCritical: percentage <= 15 && device?.state === UPowerDeviceState.Discharging
    readonly property var dischargeIcons: ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]

    function formatDuration(seconds) {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    glyph: {
        if (!device)
            return "󰁹";
        if (device.state === UPowerDeviceState.FullyCharged)
            return "󰁹";
        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return "󰂄";
        // Plugged in but not charging (e.g. charge-threshold hold) has no
        // single UPowerDeviceState value; treat any non-battery state as that.
        if (!UPower.onBattery)
            return "󰚥";
        return dischargeIcons[Math.min(9, Math.floor(percentage / 10))];
    }

    glyphColorOverride: isCritical ? Theme.color.accentPink : "transparent"

    CriticalBlink on opacity {
        running: root.isCritical
    }

    tooltipTitle: "BATTERY"
    tooltipBody: `${Math.round(percentage)}%`
    tooltipMuted: {
        if (!device)
            return "";
        if (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
            return "charging";
        if (device.state === UPowerDeviceState.FullyCharged)
            return "full";
        if (UPower.onBattery) {
            const eta = formatDuration(device.timeToEmpty);
            return eta.length > 0 ? `discharging · ~${eta}` : "discharging";
        }
        return "plugged in";
    }
}
