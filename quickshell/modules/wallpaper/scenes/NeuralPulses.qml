pragma ComponentBehavior: Bound
import QtQuick
import "neural.js" as Neural

// The fast tier (~24Hz, load-shed to ~8Hz) -- traveling signal pulses,
// the "satellite" analog: the one literally-moving, eye-catching thing.
// Each pulse is a pair of plain Rectangles (real Items, no ShapePath
// involved so no Repeater/delegate restriction applies) -- a wide,
// low-alpha disk underneath and a small crisp one on top, the filled-
// circle generalization of the double-stroke glow trick used for
// Orbital's satellite glyph. No MultiEffect: at this tick rate a real
// per-frame blur pass would cost what the mesh's slow-tier glow
// deliberately avoids paying at 24Hz.
Item {
    id: root

    required property real designScale
    required property color cLine
    required property color cLive
    required property color cCrit
    // Array of {x,y} in local coordinates within Neural.MESH_BBOX,
    // reassigned wholesale every fast tick by NeuralNet.qml.
    required property var pulses
    required property bool critical

    readonly property color glyphColor: root.critical ? root.cCrit : root.cLive

    width: 1280
    height: 800
    scale: root.designScale
    transformOrigin: Item.TopLeft

    Repeater {
        model: root.pulses
        delegate: Item {
            id: pulseDot
            required property var modelData
            x: Neural.MESH_BBOX.x + modelData.x
            y: Neural.MESH_BBOX.y + modelData.y

            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 10
                radius: 5
                color: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, 0.45)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: root.glyphColor
            }
        }
    }
}
