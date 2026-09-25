import QtQuick

// Vector redraw of Qubi's own hub-and-spoke mark (Projects/qubi/mobile/
// icon-512.png) -- a plain "Q" glyph read as a random letter rather than
// this shell's actual AI engine, and the source PNG is a mobile home-screen
// tile (opaque square background, fixed color) unsuited to a themed bar
// icon. Every other bar icon here is hand-drawn (Nerd Font glyphs, Rectangle
// shapes) rather than a raster asset, so this follows suit on Canvas
// instead of shipping a copy of Qubi's artwork that would go stale the
// moment that repo's branding changes.
Canvas {
    id: root

    property color nodeColor: "white"
    // Original artwork's center dot is a lighter tint of the same hue as
    // the six satellites, not a second color -- alpha-blending toward
    // white reproduces that without a separate theme token.
    readonly property color centerColor: Qt.lighter(nodeColor, 1.6)

    onNodeColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        const cx = width / 2;
        const cy = height / 2;
        const hexR = Math.min(width, height) * 0.38;
        const nodeR = Math.min(width, height) * 0.115;
        const centerR = Math.min(width, height) * 0.155;

        const pts = [];
        for (let i = 0; i < 6; i++) {
            const angle = -Math.PI / 2 + i * Math.PI / 3;
            pts.push({
                x: cx + hexR * Math.cos(angle),
                y: cy + hexR * Math.sin(angle)
            });
        }

        ctx.strokeStyle = root.nodeColor;
        ctx.globalAlpha = 0.4;
        ctx.lineWidth = Math.max(1, width * 0.05);
        for (let i = 0; i < 6; i++) {
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(pts[i].x, pts[i].y);
            ctx.stroke();

            const next = pts[(i + 1) % 6];
            ctx.beginPath();
            ctx.moveTo(pts[i].x, pts[i].y);
            ctx.lineTo(next.x, next.y);
            ctx.stroke();
        }

        ctx.globalAlpha = 1;
        ctx.fillStyle = root.nodeColor;
        for (let i = 0; i < 6; i++) {
            ctx.beginPath();
            ctx.arc(pts[i].x, pts[i].y, nodeR, 0, Math.PI * 2);
            ctx.fill();
        }

        ctx.fillStyle = root.centerColor;
        ctx.beginPath();
        ctx.arc(cx, cy, centerR, 0, Math.PI * 2);
        ctx.fill();
    }
}
