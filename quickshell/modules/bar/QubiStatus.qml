import QtQuick
import "../../theme"
import "file:/home/cryptix/Projects/qubi/qml"

// Qubi engine health in the bar. All the logic (socket, state derivation,
// tooltip strings) is Qubi's own QubiStatusModel; this is only how this
// shell draws it. Ultraviolet has no green/orange, so color only conveys
// the coarse off/attention/active tier; exact state lives in the tooltip,
// same split Battery.qml uses (shape = rough tier, tooltip = exact %).
BarIcon {
    id: root

    QubiStatusModel {
        id: model
    }

    glyph: "Q"
    glyphColorOverride: (model.state === "warming" || model.protocolMismatch) ? Theme.color.accentPink : (model.state === "off" || model.state === "gaming") ? Theme.color.moduleDisabledFg : model.state === "idle" ? Theme.color.rightModuleFg : Theme.color.accentPurple

    CriticalBlink on opacity {
        running: model.state === "warming"
    }

    tooltipTitle: model.title
    tooltipBody: model.body
    tooltipMuted: model.hint
}
