import QtQuick
import "../notifications"
import "../../theme"

// Live right-side modules, in display order.
Row {
    id: root

    property var barWindow: null
    property var notifServer: null
    property int notifActiveCount: 0

    // Modules sit flush (spacing 0), differentiated only by their own
    // hover-highlight region, not by a gap.
    spacing: Theme.spacing.flush

    Tray {
        barWindow: root.barWindow
    }

    QubiStatus {}
    Network {}
    Battery {}
    Backlight {}
    Volume {}
    Bluetooth {}
    Temperature {}

    Notifications {
        server: root.notifServer
        activeCount: root.notifActiveCount
    }
}
