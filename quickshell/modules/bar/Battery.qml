import QtQuick
import Quickshell.Services.UPower
import "../../theme"

// Mirrors waybar's "battery" module (bat = BAT0, states/icons/tooltips
// 1:1 from waybar.nix). Waybar's `warning: 30` threshold has no matching
// CSS rule in the current config, so it stays a no-op here too — only
// critical (<=15%) gets the pink blink.
BarIcon {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property real percentage: device?.percentage ?? 0
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
        // Plugged-in-but-not-charging (e.g. a charge-threshold hold) has no
        // single obvious UPowerDeviceState value — best-effort: anything
        // not actively discharging and not covered above. Verify against
        // `upower -i .../battery_BAT0` once a charge-threshold plateau is
        // observed live.
        if (!UPower.onBattery)
            return "󰚥";
        return dischargeIcons[Math.min(9, Math.floor(percentage / 10))];
    }

    glyphColorOverride: isCritical ? Colors.accentPink : "transparent"

    SequentialAnimation on opacity {
        running: root.isCritical
        loops: Animation.Infinite
        NumberAnimation {
            to: 0.2
            duration: 500
        }
        NumberAnimation {
            to: 1
            duration: 500
        }
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
