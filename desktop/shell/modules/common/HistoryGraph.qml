import QtQuick
import "../../services"
import "../../theme"

// Time-series line graph drawn on one Canvas (per-sample delegates would be
// thousands of nodes). Callers pass `series` and bump `repaintTick`; only
// cpuPercent is read from SystemStats, for frame-shedding.
Item {
    id: root

    // Each entry: { values: [...], color: "#rrggbb", fill: bool }
    property var series: []
    property real maxValue: 100 // 0 = autoscale to the current max across all series
    property int sampleCount: 60
    property bool showGrid: true
    property int repaintTick: 0 // bind to SystemStats.histSeq

    implicitHeight: Theme.spacing.historyGraphHeight

    readonly property real _effectiveMax: {
        if (root.maxValue > 0)
            return root.maxValue;
        let m = 0;
        for (const s of root.series)
            for (const v of (s.values ?? []))
                m = Math.max(m, v);
        return m > 0 ? m : 1;
    }

    // Under sustained high CPU, repaint every other tick (with hysteresis).
    property bool shedding: false
    readonly property bool overThreshold: SystemStats.cpuPercent > 85
    readonly property bool underThreshold: SystemStats.cpuPercent < 70
    Timer { id: shedOnTimer; interval: 5000; onTriggered: root.shedding = true }
    Timer { id: shedOffTimer; interval: 5000; onTriggered: root.shedding = false }
    onOverThresholdChanged: {
        if (root.overThreshold) {
            shedOffTimer.stop();
            shedOnTimer.restart();
        } else {
            shedOnTimer.stop();
        }
    }
    onUnderThresholdChanged: {
        if (root.underThreshold) {
            shedOnTimer.stop();
            shedOffTimer.restart();
        } else {
            shedOffTimer.stop();
        }
    }

    property int _tickCount: 0
    onRepaintTickChanged: {
        root._tickCount++;
        if (root.shedding && (root._tickCount % 2 !== 0))
            return;
        canvas.requestPaint();
    }
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onSeriesChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            if (root.showGrid) {
                ctx.globalAlpha = 1;
                ctx.strokeStyle = Theme.color.lineSoft;
                ctx.lineWidth = 1;
                ctx.setLineDash([2, 3]);
                for (const frac of [0.25, 0.5, 0.75]) {
                    const y = height * (1 - frac);
                    ctx.beginPath();
                    ctx.moveTo(0, y);
                    ctx.lineTo(width, y);
                    ctx.stroke();
                }
                ctx.setLineDash([]);
            }

            const stepX = width / Math.max(1, root.sampleCount - 1);

            for (const s of root.series) {
                const values = s.values ?? [];
                if (values.length < 2)
                    continue;
                const startI = Math.max(0, values.length - root.sampleCount);

                ctx.globalAlpha = 1;
                ctx.strokeStyle = s.color;
                ctx.lineWidth = Theme.spacing.historyGraphLineWidth;
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

                if (s.fill) {
                    ctx.lineTo((values.length - 1 - startI) * stepX, height);
                    ctx.lineTo(0, height);
                    ctx.closePath();
                    ctx.globalAlpha = Theme.spacing.historyGraphFillAlpha;
                    ctx.fillStyle = s.color;
                    ctx.fill();
                }
            }
        }
    }

    Component.onCompleted: canvas.requestPaint()
}
