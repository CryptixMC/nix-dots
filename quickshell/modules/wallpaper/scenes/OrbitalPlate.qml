import QtQuick
import "orbital-static-data.js" as OrbitalData

// The parts of the plate that never change frame to frame: latitude
// rings, the planet limb, the continent outlines, and the ASC-node
// marker. Painted once (and again on resize or a theme recolour) into
// two Canvases rather than kept as Shape nodes -- ~90 static polylines /
// ~3000 points is one texture + one draw call this way, vs. that many
// ShapePath nodes the scene graph would otherwise hold for content that
// never animates.
//
// Two canvases, not one, because the design's own SVG groups two
// different treatments: latitude rings + limb sit inside the mockup's
// `hero-glow` group (a 24px violet drop-shadow) alongside the *live*
// meridians/ground-track/orbit-ring Orbital.qml draws on top of this;
// continents and the ASC-node marker sit outside that group and never
// glow. Splitting them keeps that distinction without faking a per-path
// glow toggle inside one canvas. (The design's baked orbit ring itself
// isn't drawn from here at all -- see the comment on globeCanvas below.)
Item {
    id: root

    required property real designScale
    required property color cLine
    required property color cFaint
    required property color cMark

    anchors.fill: parent

    function roleColor(role) {
        if (role === 0)
            return root.cLine;
        if (role === 2)
            return root.cMark;
        return root.cFaint;
    }

    function strokeSeg(ctx, seg) {
        ctx.globalAlpha = seg.op;
        ctx.strokeStyle = root.roleColor(seg.role);
        ctx.setLineDash(seg.dash ?? []);
        ctx.beginPath();
        const pts = seg.pts;
        ctx.moveTo(pts[0], pts[1]);
        for (let i = 2; i < pts.length; i += 2)
            ctx.lineTo(pts[i], pts[i + 1]);
        ctx.stroke();
    }

    function repaintAll() {
        globeCanvas.requestPaint();
        plateCanvas.requestPaint();
    }

    onDesignScaleChanged: repaintAll()
    onWidthChanged: repaintAll()
    onHeightChanged: repaintAll()
    onCLineChanged: repaintAll()
    onCFaintChanged: repaintAll()
    onCMarkChanged: repaintAll()

    // Glowing group: latitude rings, limb. The design's baked orbit ring
    // (orbitRingStatic, at the fixed nominal radius) is deliberately NOT
    // drawn here anymore -- it used to sit alongside Orbital.qml's live,
    // memory-driven orbit ring as a second, separate ellipse the
    // satellite never actually followed (satelliteState() defaulted to
    // the fixed radius too), which read as a rendering bug ("why are
    // there two rings") rather than the intended nominal-vs-live
    // reference. Fixed by making the satellite orbit the live radius for
    // real; the live ring (globeLive in Orbital.qml) is now the only one.
    Canvas {
        id: globeCanvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.scale(root.designScale, root.designScale);
            ctx.lineWidth = 1;
            // Design-space blur value; ctx.scale() above carries it to
            // native resolution the same way it carries stroke widths,
            // matching the mockup's `drop-shadow(0 0 24px ...)` sized
            // against its own 1280-wide artboard.
            ctx.shadowBlur = 24;
            ctx.shadowColor = Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, 0.35);

            for (const seg of OrbitalData.latitudeRings)
                root.strokeSeg(ctx, seg);

            ctx.globalAlpha = 1;
            ctx.setLineDash([]);
            ctx.strokeStyle = root.cLine;
            ctx.beginPath();
            ctx.arc(OrbitalData.limb.cx, OrbitalData.limb.cy, OrbitalData.limb.r, 0, Math.PI * 2);
            ctx.stroke();

            ctx.restore();
        }
    }

    // Non-glowing group: continents, ASC-node marker.
    Canvas {
        id: plateCanvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.scale(root.designScale, root.designScale);
            ctx.lineWidth = 1;

            for (const seg of OrbitalData.continents)
                root.strokeSeg(ctx, seg);

            root.strokeSeg(ctx, OrbitalData.ascNode.leaderLine);
            ctx.globalAlpha = 1;
            ctx.setLineDash([]);
            ctx.fillStyle = root.cMark;
            ctx.beginPath();
            ctx.arc(OrbitalData.ascNode.dot.cx, OrbitalData.ascNode.dot.cy, OrbitalData.ascNode.dot.r, 0, Math.PI * 2);
            ctx.fill();
            root.strokeSeg(ctx, OrbitalData.ascNode.underline);

            ctx.restore();
        }
    }

    Component.onCompleted: repaintAll()
}
