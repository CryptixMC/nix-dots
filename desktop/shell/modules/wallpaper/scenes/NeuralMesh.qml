pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Effects
import "neural.js" as Neural

// Static mesh (nodes + edges). Topology is set once; per-tick intensity arrives
// in separate index-aligned arrays to avoid delegate churn from reassigning models.
// Edges use Instantiator + manual Shape.data because a Repeater can't delegate a
// ShapePath (not an Item). The glow is sized to MESH_BBOX, not the full stage, and
// is only affordable because this layer updates at ~3Hz (load-shed to ~1Hz).
Item {
    id: root

    required property real designScale
    required property color cLine
    required property color cMark
    // Stable topology: {layer,x,y,coreIndex?} / {fromLayer,toLayer,x1,y1,x2,y2},
    // in local coordinates within Neural.MESH_BBOX.
    required property var nodes
    required property var edges
    // Per-tick, index-aligned to nodes/edges above.
    required property var nodeIntensities
    required property var edgeIntensities

    width: 1280
    height: 800
    scale: root.designScale
    transformOrigin: Item.TopLeft

    Item {
        id: glowGroup
        x: Neural.MESH_BBOX.x
        y: Neural.MESH_BBOX.y
        width: Neural.MESH_BBOX.w
        height: Neural.MESH_BBOX.h

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, 0.35)
            shadowBlur: 0.6
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }

        Shape {
            id: edgeShape
            anchors.fill: parent
            Instantiator {
                model: root.edges
                delegate: ShapePath {
                    id: edgePath
                    required property var modelData
                    required property int index
                    strokeColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, root.edgeIntensities[index] ?? 0)
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathPolyline {
                        path: [Qt.point(edgePath.modelData.x1, edgePath.modelData.y1),
                               Qt.point(edgePath.modelData.x2, edgePath.modelData.y2)]
                    }
                }
                onObjectAdded: (index, object) => edgeShape.data.push(object)
                onObjectRemoved: (index, object) => {
                    const i = edgeShape.data.indexOf(object);
                    if (i >= 0)
                        edgeShape.data.splice(i, 1);
                }
            }
        }

        Repeater {
            model: root.nodes
            delegate: Rectangle {
                id: nodeDot
                required property var modelData
                required property int index
                x: modelData.x - Neural.NODE_R
                y: modelData.y - Neural.NODE_R
                width: Neural.NODE_R * 2
                height: Neural.NODE_R * 2
                radius: width / 2
                color: root.cMark
                opacity: root.nodeIntensities[index] ?? 0
            }
        }
    }
}
