import QtQuick
import "../../theme"

// Tiny single-series line graph for bar widgets; no grid or frame-shedding.
Item {
    id: root

    property var values: [] // oldest-to-newest
    property color color: Theme.color.accentPurple
    property real maxValue: 0 // 0 = autoscale to this series' own max
    property int sampleCount: 30
    property int repaintTick: 0 // bind to SystemStats.histSeq

    implicitWidth: Theme.spacing.sparklineWidth
    implicitHeight: Theme.spacing.sparklineHeight

    readonly property real _effectiveMax: {
        if (root.maxValue > 0)
            return root.maxValue;
        let m = 0;
        for (const v of root.values)
            m = Math.max(m, v);
        return m > 0 ? m : 1;
    }

    onRepaintTickChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onValuesChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const values = root.values ?? [];
            if (values.length < 2)
                return;

            const stepX = width / Math.max(1, root.sampleCount - 1);
            const startI = Math.max(0, values.length - root.sampleCount);

            ctx.strokeStyle = root.color;
            ctx.lineWidth = Theme.spacing.sparklineLineWidth;
            ctx.beginPath();
            for (let i = startI; i < values.length; i++) {
                const x = (i - startI) * stepX;
                const y = height * (1 - Math.min(1, values[i] / root._effectiveMax));
                if (i === startI)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.stroke();
        }
    }

    Component.onCompleted: canvas.requestPaint()
}
