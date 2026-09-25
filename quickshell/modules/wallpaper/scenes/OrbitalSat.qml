pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Shapes
import "orbital.js" as Orbital
import "orbital-static-data.js" as OrbitalData

// The fast (~24Hz, load-shed to ~8Hz under CPU pressure) layer: the
// satellite glyph, its lead arc, and its follow-tag leader/dot. Built
// once as static local Shape geometry and moved as a unit via x/y/
// rotation/scale on satBody -- no per-frame geometry rebuild, matching
// the mockup's own `<g transform="translate(...) rotate(...) scale(...)">`.
//
// Glow: the mockup's `.live-glow` class is a 6px violet (cLine, not the
// satellite's own white) drop-shadow around the lead arc + satellite
// body. A per-frame MultiEffect shadow pass here would mean rebuilding a
// ~1280x800 FBO 24x/sec (the same "full-screen Canvas at 24Hz" cost the
// plan explicitly avoided for this layer) -- so instead this draws each
// glowing piece TWICE: a wider, low-alpha cLine pass underneath, a crisp
// pass on top. Cheap (Shape node count, not a rasterized pass) and, at
// the satellite's on-screen size, visually indistinguishable from a true
// gaussian blur. The follow-tag leader/dot is a separate, non-glowing
// group in the mockup (a plain opacity-only <g>) and stays single-pass.
//
// Repeater (not Instantiator) with a ShapePath delegate logs "Delegate
// must be of Item type" and silently produces no children -- confirmed
// against the real quickshell binary, not just qmllint (Repeater assumes
// Item delegates; ShapePath isn't one). Every variable-count ShapePath
// list here uses Instantiator instead, manually appended into the
// owning Shape's `data` list (Shape's default property, a plain
// QQmlListProperty<QObject> — confirmed via quickshell-shapes'
// metatypes — so a dynamically-created ShapePath just needs pushing
// into it, same idiom this repo's ThemeLoader.qml already uses
// Instantiator for, just with manual data-list management added since
// that usage doesn't need one).
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
    // Fixed-capacity (Orbital.LEAD_ARC_CAP) array of flat [x,y,x,y,...]
    // design-space point runs from Orbital.leadArc(), or null per slot --
    // see the padArray comment in orbital.js for why this is padded
    // rather than a variable-length array.
    property var leadArcRuns: []
    // {px,py,mx,my,lx,ly,rx0,rx1,labelLeft,labelTop} from Orbital.tagPlacement(), or null.
    property var tag: null

    // Always the theme's purple accent (cLine, same colour as the globe
    // linework) -- this used to be cLive (the theme's "live" role, which
    // in ultraviolet-v2 is a near-white base07, not purple) and flip to a
    // critical (pink) colour whenever tempCritical/batteryCritical went
    // true. Now a single, deliberately-picked purple, always.
    readonly property color glyphColor: root.cLine
    // Counter-scales satBody's own `scale: satK` so stroke width stays a
    // constant on-screen thickness regardless of the glyph's near/far
    // perspective size -- the mockup's `vector-effect="non-scaling-stroke"`.
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

    // Shared by every Instantiator below: append newly-created delegates
    // into the target Shape's `data` list, remove them again on model
    // shrink. `target` is passed explicitly (rather than each call site
    // repeating the push/splice body) since the only thing that differs
    // per site is which Shape owns the paths.
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
            // Fixed-capacity model (Orbital.LEAD_ARC_CAP), not the live
            // array itself -- see the matching comment on globeShape's
            // Instantiators in Orbital.qml for why (avoids destroying and
            // recreating these ShapePaths every fast tick).
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
    // Fixed count (one ShapePath, declared directly) -- no
    // Instantiator/Repeater needed here, only the lead-arc/glyph lists
    // above vary in count frame to frame.
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
