import QtQuick
import "../notifications"
import "../../theme"

// Live right-side modules, in display order.
//
// Deliberately trimmed to seven -- this bar is 26px tall, and it had grown
// to thirteen modules across this session's additions (NetSpeed,
// ResourceGraph, QuickSettings) stacked on top of the original nine. Cut
// rather than kept "for completeness": Backlight, Volume, Bluetooth and
// Temperature are all either fully redundant with QuickSettingsPanel (its
// toggle grid already has Bluetooth; its sliders already have volume/mic/
// brightness) or covered by Osd.qml's transient feedback on the same
// hardware-key presses that used to need a bar icon to see the result of.
// NetSpeed/ResourceGraph were nice-to-have telemetry with no real urgency
// to be always-visible -- Monitor already covers that ground in more
// detail than a bar icon ever could. None of the removed files were
// deleted, only unwired here, so any of this is a one-line revert if it's
// missed in practice.
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
    Media {}
    Network {}
    Battery {}
    QuickSettings {}

    Notifications {
        server: root.notifServer
        activeCount: root.notifActiveCount
    }
}
