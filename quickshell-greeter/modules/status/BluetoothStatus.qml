import QtQuick
import Quickshell.Bluetooth
import "../../theme"

// Trimmed adaptation of quickshell/modules/bar/Bluetooth.qml — read-only
// status (no click-to-open blueman-manager; nothing to manage pre-login).
Row {
    id: root
    spacing: 6
    visible: adapter !== null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.state === BluetoothAdapterState.Enabled
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰂯"
        color: root.enabled ? Colors.mutedFg : Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.25)
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.connectedDevices.length > 0
        text: root.connectedDevices.length > 0 ? `${root.connectedDevices.length} connected` : ""
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
