import QtQuick
import "../bar"
import "../../theme"

// Replaces the static "󰂚" placeholder in RightModules.qml. Waybar's own
// "custom/notifications" module is a static fake (hardcoded "dnd: off")
// since it never ran a real daemon — see NotifierServer.qml for why this
// one can be real instead.
//
// Click opens the Notification Centre (history + DND toggle + clear-all)
// rather than directly toggling DND on the bar icon -- a bare click-to-
// toggle had no way to ever SEE what came in, only mute it; the popup adds
// that without losing the one-click DND path (it's still one click away,
// just inside the popup instead of on the icon itself).
BarIcon {
    id: root

    property var server: null
    // Sourced from Toast.qml's Repeater.count (threaded down via
    // shell.qml→Bar.qml→RightModules.qml) rather than computed locally —
    // see Toast.qml's activeCount comment for why a hand-rolled
    // trackedNotifications.values.length read doesn't reliably update.
    property int activeCount: 0

    // Outline at rest (nothing active, DND off) is the design system's
    // default state; solid bell when there's something to look at, solid
    // slashed bell when DND is a deliberate on choice -- both are "selected"
    // states in the outline/filled sense, just two different selections.
    // \u{} escapes, not literal glyph bytes (FilesTree.qml's chevron notes
    // why), and verified against nerd-fonts' real glyphnames.json this
    // session after finding Bluetooth.qml's matching comment was wrong.
    glyph: NotificationState.dnd ? "\u{F009B}" // md-bell_off
        : activeCount > 0 ? "\u{F009A}" // md-bell
        : "\u{F009C}" // md-bell_outline
    glyphColorOverride: (activeCount > 0 && !NotificationState.dnd) ? Theme.color.accentPink : "transparent"

    onClickFn: () => popup.visible = !popup.visible

    tooltipTitle: "NOTIFICATIONS"
    tooltipBody: NotificationState.dnd ? "do not disturb: on" : `${activeCount} active`
    tooltipMuted: "click to open"

    NotifCenterPopup {
        id: popup
        anchorItem: root
        server: root.server
    }
}
