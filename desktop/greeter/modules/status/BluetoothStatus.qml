import QtQuick
import Quickshell.Bluetooth
import "../../theme"

// Read-only Bluetooth status.
Row {
    id: root
    spacing: 6
    visible: adapter !== null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.state === BluetoothAdapterState.Enabled
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []

    Text {
        anchors.verticalCenter: parent.verticalCenter
        // \u{} escapes: raw glyph bytes in this codepoint range got corrupted.
        text: root.enabled ? "\u{F00AF}" : "\u{F00B2}" // md-bluetooth / md-bluetooth_off
        color: root.enabled ? Colors.textBody : Colors.textDim
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.connectedDevices.length > 0
        text: root.connectedDevices.length > 0 ? `${root.connectedDevices.length} connected` : ""
        color: Colors.textBody
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
