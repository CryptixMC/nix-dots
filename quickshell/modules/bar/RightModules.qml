import QtQuick
import "../notifications"

// Live right-side modules, in the same order as waybar.nix's modules-right.
Row {
    id: root

    property var barWindow: null
    property var notifServer: null
    property int notifActiveCount: 0

    // waybar's top-level `spacing = 0` applies between modules-right
    // entries too — modules sit flush, differentiated only by their own
    // hover-highlight region, not by a gap.
    spacing: 0

    Tray {
        barWindow: root.barWindow
    }

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
