import QtQuick
import "../bar"
import "../../theme"

// Replaces the static "󰂚" placeholder in RightModules.qml. Waybar's own
// "custom/notifications" module is a static fake (hardcoded "dnd: off")
// since it never ran a real daemon — see NotificationServer.qml for why
// this one can be real instead.
BarIcon {
    id: root

    property var server: null
    // Sourced from Toast.qml's Repeater.count (threaded down via
    // shell.qml→Bar.qml→RightModules.qml) rather than computed locally —
    // see Toast.qml's activeCount comment for why a hand-rolled
    // trackedNotifications.values.length read doesn't reliably update.
    property int activeCount: 0

    glyph: NotificationState.dnd ? "󰂛" : "󰂚"
    glyphColorOverride: (activeCount > 0 && !NotificationState.dnd) ? Colors.accentPink : "transparent"

    onClickFn: () => NotificationState.toggleDnd()

    tooltipTitle: "NOTIFICATIONS"
    tooltipBody: NotificationState.dnd ? "do not disturb: on" : `${activeCount} active`
    tooltipMuted: "click to toggle DND"
}
