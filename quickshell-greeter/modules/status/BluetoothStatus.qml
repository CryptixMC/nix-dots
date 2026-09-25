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
        // \u{} escape rather than a literal glyph byte (this codepoint
        // range corrupted to an empty string when written raw earlier this
        // session). F009C was also wrong on its own terms -- re-verified
        // against nerd-fonts' real glyphnames.json in the main shell's own
        // Bluetooth.qml this session: F009C is md-bell_outline, not a
        // bluetooth glyph at all, it just happened to render *something*.
        // F00B2 (md-bluetooth_off, a slashed bluetooth) is the pair the
        // main shell actually settled on; this file just hadn't caught up.
        text: root.enabled ? "\u{F00AF}" : "\u{F00B2}" // md-bluetooth / md-bluetooth_off
        // textDim (base0F, == moduleDisabledFg) when off, matching
        // Bluetooth.qml's glyphColorOverride -- a dim violet, not the
        // near-invisible base04 grey this file used before.
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
