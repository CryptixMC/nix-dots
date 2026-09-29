import QtQuick
import "../../theme"
import "popups"

// Bar trigger for QuickSettingsPanel.qml; filled glyph while the panel is open.
BarIcon {
    id: root

    glyph: popup.visible ? "\u{F0570}" : "\u{F11D9}" // md-view_grid / md-view_grid_outline
    glyphColorOverride: popup.visible ? Theme.color.accentPurple : "transparent"

    onClickFn: () => popup.visible = !popup.visible

    tooltipTitle: "QUICK SETTINGS"
    tooltipBody: "click to open"

    QuickSettingsPanel {
        id: popup
        anchorItem: root
    }
}
