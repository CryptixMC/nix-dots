pragma ComponentBehavior: Bound
import QtQuick

// HUD text layer, kept outside the scaled stage because scaling Text blurs its
// glyph atlas; design-space values are multiplied by designScale instead.
// `model` is one entry per Text item (labels and values separately), built by Orbital.qml.
Item {
    id: root

    required property real designScale
    required property color cFaint
    property var model: []

    anchors.fill: parent

    // Fixed row rules, in design-space y.
    readonly property var ruleYs: [222, 250, 278, 306, 334]
    Repeater {
        model: root.ruleYs
        delegate: Rectangle {
            required property real modelData
            x: 96 * root.designScale
            y: modelData * root.designScale
            width: 280 * root.designScale
            height: Math.max(1, root.designScale)
            color: root.cFaint
            opacity: 0.55
        }
    }

    Repeater {
        model: root.model
        delegate: Text {
            id: label
            required property var modelData

            text: modelData.text
            color: modelData.color
            font.family: modelData.family ?? "JetBrainsMono Nerd Font Mono"
            font.pixelSize: modelData.size * root.designScale
            font.bold: modelData.bold ?? false
            font.letterSpacing: (modelData.ls ?? 0) * modelData.size * root.designScale
            renderType: Text.NativeRendering
            rotation: modelData.rotate ?? 0
            transformOrigin: Item.TopLeft

            x: modelData.align === "right" ? (modelData.x + (modelData.w ?? 0)) * root.designScale - width : modelData.x * root.designScale
            y: modelData.y * root.designScale
        }
    }
}
