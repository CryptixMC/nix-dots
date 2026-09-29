pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Shapes
import "orbital.js" as Orbital
import "orbital-static-data.js" as OrbitalData

// Fast layer (~24Hz, load-shed to ~8Hz): satellite glyph, lead arc and follow tag,
// built once and moved as a unit via x/y/rotation/scale.
// Glow is faked by drawing each piece twice (wide low-alpha + crisp) because a
// per-frame MultiEffect would re-render a full-stage FBO 24x/sec.
// Variable-count ShapePath lists use Instantiator + manual Shape.data management:
// a Repeater can't delegate a ShapePath (not an Item) and silently yields nothing.
Item {
    id: root

    required property real designScale
    required property color cLine

    // Design-space (1280x800) satellite state, updated every fast tick.
    property real satX: 0
    property real satY: 0
    property real satAngle: 0
    property real satK: 1
    // 1 = normal, 0.35 = offline-but-not-occluded ("dead but visible"),
    // 0 = geometrically occluded by the planet.
    property real satDimOpacity: 1
    // Fixed-capacity (Orbital.LEAD_ARC_CAP) slots of flat [x,y,...] runs or null;
    // see padArray in orbital.js.
    property var leadArcRuns: []
    // {px,py,mx,my,lx,ly,rx0,rx1,labelLeft,labelTop} from Orbital.tagPlacement(), or null.
    property var tag: null

    // Always the purple accent, never the live/critical roles.
    readonly property color glyphColor: root.cLine
    // Counter-scales satBody's scale so strokes keep constant on-screen width.
    readonly property real nonScaleStrokeW: root.satK > 0.001 ? 1 / root.satK : 1000

    readonly property var _glyphSegments: {
        const out = [];
        for (const p of OrbitalData.satGlyph) {
            if (p.tag === "rect") {
                out.push({ op: p.op, points: [p.x, p.y, p.x + p.w, p.y, p.x + p.w, p.y + p.h, p.x, p.y + p.h, p.x, p.y] });
            } else if (p.tag === "ellipse") {
                const pts = [];
                const N = 32;
                for (let i = 0; i <= N; i++) {
                    const a = (2 * Math.PI * i) / N;
                    pts.push(p.cx + p.rx * Math.cos(a), p.cy + p.ry * Math.sin(a));
                }
                out.push({ op: p.op, points: pts });
            } else if (p.tag === "path") {
                for (const run of p.runs)
                    out.push({ op: p.op, points: run });
            }
        }
        return out;
    }

    // Shared Instantiator hooks that add/remove delegates in a Shape's data list.
    function attachTo(shape, index, object) {
        shape.data.push(object);
    }
    function detachFrom(shape, index, object) {
        const i = shape.data.indexOf(object);
        if (i >= 0)
            shape.data.splice(i, 1);
    }

    width: 1280
    height: 800
    scale: root.designScale
    transformOrigin: Item.TopLeft

    // === live-glow group: lead arc + satellite body ===
    Item {
        id: glowGroup
        anchors.fill: parent
        opacity: root.satDimOpacity

        Shape {
            id: leadArcGlow
            anchors.fill: parent
            // Fixed-capacity model so ShapePaths aren't recreated every fast tick.
            Instantiator {
                model: Orbital.LEAD_ARC_CAP
                delegate: ShapePath {
                    id: leadArcGlowPath
                    required property int index
                    readonly property var entry: root.leadArcRuns[leadArcGlowPath.index] ?? null
                    strokeColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, leadArcGlowPath.entry ? 0.45 : 0)
                    strokeWidth: 6
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathPolyline { path: leadArcGlowPath.entry ? Orbital.toPoints(leadArcGlowPath.entry) : [] }
                }
                onObjectAdded: (index, object) => root.attachTo(leadArcGlow, index, object)
                onObjectRemoved: (index, object) => root.detachFrom(leadArcGlow, index, object)
            }
        }
        Shape {
            id: leadArcCrisp
            anchors.fill: parent
            Instantiator {
                model: Orbital.LEAD_ARC_CAP
                delegate: ShapePath {
                    id: leadArcCrispPath
                    required property int index
                    readonly property var entry: root.leadArcRuns[leadArcCrispPath.index] ?? null
                    strokeColor: leadArcCrispPath.entry ? root.glyphColor : Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, 0)
                    strokeWidth: 2
                    fillColor: "transparent"
                    PathPolyline { path: leadArcCrispPath.entry ? Orbital.toPoints(leadArcCrispPath.entry) : [] }
                }
                onObjectAdded: (index, object) => root.attachTo(leadArcCrisp, index, object)
                onObjectRemoved: (index, object) => root.detachFrom(leadArcCrisp, index, object)
            }
        }

        Item {
            id: satBody
            x: root.satX
            y: root.satY
            rotation: root.satAngle
            scale: root.satK

            Shape {
                id: satGlow
                Instantiator {
                    model: root._glyphSegments
                    delegate: ShapePath {
                        id: satGlowPath
                        required property var modelData
                        strokeColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, 0.45 * modelData.op)
                        strokeWidth: root.nonScaleStrokeW * 4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathPolyline { path: Orbital.toPoints(satGlowPath.modelData.points) }
                    }
                    onObjectAdded: (index, object) => root.attachTo(satGlow, index, object)
                    onObjectRemoved: (index, object) => root.detachFrom(satGlow, index, object)
                }
            }
            Shape {
                id: satCrisp
                Instantiator {
                    model: root._glyphSegments
                    delegate: ShapePath {
                        id: satCrispPath
                        required property var modelData
                        strokeColor: Qt.rgba(root.glyphColor.r, root.glyphColor.g, root.glyphColor.b, modelData.op)
                        strokeWidth: root.nonScaleStrokeW
                        fillColor: "transparent"
                        PathPolyline { path: Orbital.toPoints(satCrispPath.modelData.points) }
                    }
                    onObjectAdded: (index, object) => root.attachTo(satCrisp, index, object)
                    onObjectRemoved: (index, object) => root.detachFrom(satCrisp, index, object)
                }
            }
        }
    }

    // === follow-tag leader + dot (no glow, own opacity in the mockup) ===
    Shape {
        anchors.fill: parent
        visible: root.tag !== null
        opacity: root.satDimOpacity
        ShapePath {
            strokeColor: root.glyphColor
            strokeWidth: 1
            fillColor: "transparent"
            PathPolyline {
                path: root.tag ? Orbital.toPoints([root.tag.px, root.tag.py, root.tag.mx, root.tag.my, root.tag.lx, root.tag.ly]) : []
            }
        }
    }
    Rectangle {
        visible: root.tag !== null
        opacity: root.satDimOpacity
        x: (root.tag ? root.tag.px : 0) - 2
        y: (root.tag ? root.tag.py : 0) - 2
        width: 4
        height: 4
        radius: 2
        color: root.glyphColor
    }
}
