pragma ComponentBehavior: Bound
import QtQuick

// The HUD text layer -- deliberately NOT inside the designScale-scaled
// stage (Canvas/Shape layers scale their whole coordinate space; text
// does the opposite here) because scaling a Text item scales its
// rasterized glyph atlas, and 11px design text goes visibly soft at the
// 2x native scale this wallpaper typically runs at. Every geometric value
// below is a DESIGN-space number multiplied by designScale at bind time
// instead, so glyphs are laid out and rasterized at native resolution.
//
// `model` is a flat array of one entry per Text item -- a label and its
// value are two separate entries, not one "row" object -- built by
// Orbital.qml from the live readout mapping (see the plan's "Readout
// mapping" section). This component only knows how to lay a model out;
// it has no opinion on what the numbers mean.
Item {
    id: root

    required property real designScale
    required property color cFaint
    property var model: []

    anchors.fill: parent

    // The four horizontal rules between HUD rows (y 222/250/278/306/334
    // in the design) are fixed structure, not data -- drawn directly
    // rather than routed through `model`.
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
