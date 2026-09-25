import QtQuick
import Quickshell.Bluetooth
import "../../theme"

// BlueZ is confirmed live on this host and Quickshell ships a real
// binding, so state (adapter power, connected devices) is live rather
// than a static placeholder. Click opens a device flyout (BluetoothPopup.qml)
// instead of launching
// blueman-manager directly, same upgrade as Volume/Network — blueman is
// still one click away via the flyout's "›" link.
BarIcon {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.state === BluetoothAdapterState.Enabled
    readonly property var connectedDevices: adapter ? adapter.devices.values.filter(d => d.connected) : []

    // Filled once the adapter's actually on, per the design system's
    // outline-at-rest/filled-when-selected rule -- but the earlier claim
    // that F009C is "md-bluetooth_outline" was wrong (re-verified against
    // nerd-fonts' real glyphnames.json this session: F009C is actually
    // md-bell_outline, an entirely different icon that happened to render
    // something plausible-looking instead of erroring). No bluetooth
    // outline glyph exists in the MDI set at all -- md-bluetooth_off (a
    // bluetooth glyph with a slash through it) is the real "disabled"
    // icon MDI actually provides for this family, so that's the pair now.
    // \u{} escape, not a literal glyph byte -- this exact codepoint range
    // silently corrupted to an empty string when written as raw UTF-8
    // earlier this session (see FilesTree.qml's chevron).
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
