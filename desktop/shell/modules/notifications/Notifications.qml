import QtQuick
import "../bar"
import "../../theme"

// Bar bell icon; click opens the Notification Centre (history, DND, clear-all).
BarIcon {
    id: root

    property var server: null
    // Comes from Toast's Repeater.count; trackedNotifications.values.length
    // doesn't reliably notify.
    property int activeCount: 0

    // Outline at rest, filled when active or DND. Use \u{} escapes, not literal glyph bytes.
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
