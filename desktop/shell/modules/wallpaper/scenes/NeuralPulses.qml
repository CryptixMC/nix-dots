pragma ComponentBehavior: Bound
import QtQuick
import "neural.js" as Neural

// Fast tier (~24Hz, load-shed to ~8Hz): traveling signal pulses. Each is two
// plain Rectangles (soft halo + crisp core); no MultiEffect since a per-frame blur
// at this rate is too expensive.
Item {
    id: root

    required property real designScale
    required property color cLine
    required property color cLive
    required property color cCrit
    // Array of {x,y} within Neural.MESH_BBOX, reassigned every fast tick.
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
