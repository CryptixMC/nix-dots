import QtQuick
import Quickshell.Bluetooth
import "../../theme"

// Beyond strict waybar parity: waybar's own "custom/bluetooth" module is a
// static fake (hardcoded "Connected" tooltip) — BlueZ is confirmed live on
// this host and Quickshell ships a real binding, so this is live instead.
BarIcon {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.state === BluetoothAdapterState.Enabled
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []

    glyph: "󰂯"
    // No confirmed "bluetooth-off" nerd-font glyph — dim the same glyph
    // instead of guessing one.
    glyphColorOverride: enabled ? "transparent" : Colors.moduleDisabledFg

    clickCommand: "blueman-manager"

    tooltipTitle: "BLUETOOTH"
    tooltipBody: connectedDevices.length > 0 ? connectedDevices.map(d => d.deviceName).join(", ") : "no devices connected"
    tooltipMuted: adapter ? (enabled ? "powered on" : "powered off") : "no adapter"
}
