import QtQuick
import Quickshell.Bluetooth
import "../../theme"
import "popups"

// Bluetooth state from Quickshell's BlueZ binding. Click opens a device
// flyout (BluetoothPopup.qml), which links to blueman.
BarIcon {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.state === BluetoothAdapterState.Enabled
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []

    // MDI has no bluetooth outline glyph, so off uses md-bluetooth_off.
    // Use \u{} escapes: this codepoint range corrupted when written as raw UTF-8.
    glyph: root.enabled ? "\u{F00AF}" : "\u{F00B2}" // md-bluetooth / md-bluetooth_off
    glyphColorOverride: enabled ? "transparent" : Theme.color.moduleDisabledFg

    onClickFn: () => popup.visible = !popup.visible

    tooltipTitle: "BLUETOOTH"
    tooltipBody: connectedDevices.length > 0 ? connectedDevices.map(d => d.deviceName).join(", ") : "no devices connected"
    tooltipMuted: adapter ? (enabled ? "powered on" : "powered off") : "no adapter"

    BluetoothPopup {
        id: popup
        anchorItem: root
        adapter: root.adapter
    }
}
