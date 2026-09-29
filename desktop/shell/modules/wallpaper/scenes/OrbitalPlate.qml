import QtQuick
import "orbital-static-data.js" as OrbitalData

// Static plate layers (latitude rings, limb, continents, ASC-node marker), painted
// into canvases on resize/recolour: one texture instead of ~90 ShapePath nodes.
// Two canvases because only rings + limb get the design's glow.
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

    // Glowing group: latitude rings, limb. The nominal orbit ring is intentionally not
    // drawn; Orbital.qml's live ring is the only one.
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
            // Design-space blur; ctx.scale() carries it to native resolution.
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
