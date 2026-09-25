pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Effects
import "neural.js" as Neural

// The static mesh (nodes + edges) -- the "globe" analog. Positions are
// fixed after layout(); only per-tick intensity changes, via a wholesale-
// reassigned flat array each delegate reads by its own `index`, never by
// reassigning the topology itself -- reassigning ~130 elements to a
// Repeater/Instantiator model every tick risks full delegate churn if Qt
// doesn't diff by identity, so the actual node/edge lists are handed in
// once and never touched again by NeuralNet.qml unless the real core
// count changes.
//
// Nodes are plain Rectangles (real Items) via a plain Repeater -- no
// ShapePath-delegate restriction applies to them. Edges are genuine open
// line strokes, so they use the same Instantiator + manual Shape.data
// management the Orbital scene's meridians use (Repeater with a
// ShapePath delegate silently produces zero children -- "Delegate must
// be of Item type" -- because ShapePath isn't an Item).
//
// The whole thing is wrapped in one MultiEffect glow, sized to the
// mesh's own bounding box (Neural.MESH_BBOX) rather than the full
// 1280x800 stage -- unlike Orbital's globe, which legitimately fills
// most of the frame, this diagram occupies a fraction of it, and sizing
// the glow to the full stage would waste most of the blur pass on empty
// space. A real per-frame MultiEffect shadow is only affordable here
// because this layer updates at ~3Hz (load-shed to ~1Hz), not the ~24Hz
// the traveling pulses (NeuralPulses.qml) update at.
Item {
    id: root

    required property real designScale
    required property color cLine
    required property color cMark
    // Stable topology -- {layer,x,y,coreIndex?} / {fromLayer,toLayer,x1,y1,x2,y2},
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
