import QtQuick
import "orbital.js" as Orbital

// The dot-grid background, replicating the mockup's CSS
// `radial-gradient(circle at 1px 1px, ...) background-size: 24px 24px`.
// Painted once into a canvas oversized by one grid pitch in each
// dimension, then drifted purely by translating the canvas item's x/y --
// no repaint needed for motion, only for resize/recolour (matches
// OrbitalPlate.qml's "transform only" layer A from the plan).
Item {
    id: root

    required property real designScale
    required property color cFaint
    // Native-pixel drift offset, wrapped by the caller into
    // [0, Orbital.GRID_PITCH * designScale) so the oversize margin never
    // runs out.
    property real offsetX: 0
    property real offsetY: 0

    anchors.fill: parent
    clip: true

    Canvas {
        id: canvas
        x: -root.offsetX
        y: -root.offsetY
        width: root.width + Orbital.GRID_PITCH * root.designScale
        height: root.height + Orbital.GRID_PITCH * root.designScale
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.scale(root.designScale, root.designScale);
            ctx.fillStyle = Qt.rgba(root.cFaint.r, root.cFaint.g, root.cFaint.b, 0.3);
            const pitch = Orbital.GRID_PITCH;
            const cols = Math.ceil(width / root.designScale / pitch) + 1;
            const rows = Math.ceil(height / root.designScale / pitch) + 1;
            for (let i = 0; i < cols; i++) {
                for (let j = 0; j < rows; j++) {
                    ctx.beginPath();
                    ctx.arc(i * pitch + 1, j * pitch + 1, 1, 0, Math.PI * 2);
                    ctx.fill();
                }
            }
            ctx.restore();
        }

        Component.onCompleted: requestPaint()
    }

    function repaint() {
        canvas.requestPaint();
    }

    onDesignScaleChanged: repaint()
    onWidthChanged: repaint()
    onHeightChanged: repaint()
    onCFaintChanged: repaint()
}
