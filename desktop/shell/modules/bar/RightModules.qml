import QtQuick
import "../notifications"
import "../../theme"

// Right-side modules, in display order. Kept short for the 26px bar:
// Backlight, Volume, Bluetooth, Temperature, NetSpeed and ResourceGraph
// are covered by QuickSettingsPanel, Osd.qml or Monitor, and are left
// unwired (not deleted) so re-adding one is a one-line change.
Row {
    id: root

    property var notifServer: null
    property int notifActiveCount: 0

    spacing: Theme.spacing.flush

    Tray {}

    QubiStatus {}
    Media {}
    Network {}
    Battery {}
    QuickSettings {}

    Notifications {
        server: root.notifServer
        activeCount: root.notifActiveCount
    }
}
