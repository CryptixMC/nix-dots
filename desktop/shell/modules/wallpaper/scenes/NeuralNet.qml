import QtQuick
import "../../../theme"
import "../../../services"
import "orbital.js" as Orbital
import "neural.js" as Neural
import "scene-palette.js" as ScenePalette

// Live neural-network diagram driven by real system stats; reuses OrbitalGrid and OrbitalHud.
Item {
    id: root

    // Set by WallpaperContent.qml.
    required property bool shouldAnimate

    // False on the lock screen, where the HUD would collide with LockView's content.
    property bool showHud: true

    readonly property real designScale: Math.max(width / 1280, height / 800)

    // Hidden until Theme.color resolves, so fallback colours never flash.
    opacity: Theme.resolved ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

    // === palette (shared with Orbital.qml, see scene-palette.js) ===
    readonly property var _palette: ScenePalette.derivePalette(Theme.color)
    readonly property color cLine: root._palette.cLine
    readonly property color cFaint: root._palette.cFaint
    readonly property color cLive: root._palette.cLive
    readonly property color cCrit: root._palette.cCrit
    readonly property color cMark: root._palette.cMark
    readonly property color cValue: root._palette.cValue

    // === SystemStats lifecycle ===
    onShouldAnimateChanged: {
        if (shouldAnimate)
            SystemStats.acquire();
        else
            SystemStats.release();
    }
    Component.onCompleted: {
        if (root.shouldAnimate)
            SystemStats.acquire();
        root._maybeRelayout();
    }
    Component.onDestruction: {
        if (root.shouldAnimate)
            SystemStats.release();
    }

    // === load shedding ===
    property bool shedding: false
    readonly property bool overThreshold: SystemStats.cpuPercent > 85
    readonly property bool underThreshold: SystemStats.cpuPercent < 70
    Timer { id: shedOnTimer; interval: 5000; onTriggered: root.shedding = true }
    Timer { id: shedOffTimer; interval: 5000; onTriggered: root.shedding = false }
    onOverThresholdChanged: {
        if (overThreshold) { shedOffTimer.stop(); shedOnTimer.restart(); } else { shedOnTimer.stop(); }
    }
    onUnderThresholdChanged: {
        if (underThreshold) { shedOnTimer.stop(); shedOffTimer.restart(); } else { shedOffTimer.stop(); }
    }

    // === sweep motion ===
    // Integrated per tick (not t/sweepSeconds) so a CPU spike accelerates the
    // sweep instead of teleporting it.
    property real totalSweeps: 0
    property real smoothedCpuAvg: SystemStats.cpuPercent
    Behavior on smoothedCpuAvg { SmoothedAnimation { velocity: 25 } }

    readonly property real sweepPos: root.totalSweeps - Math.floor(root.totalSweeps)
    readonly property int epoch: Math.floor(root.totalSweeps)

    // === mesh topology (rebuilt only when the real core count changes) ===
    // Not a binding: cpuPerCore is reassigned every tick and fresh layouts would
    // churn delegates, so _maybeRelayout() compares by value first.
    property var layerCounts: []
    property var meshLayout: ({ nodes: [], edges: [] })

    function _maybeRelayout() {
        const counts = Neural.layerCounts(SystemStats.cpuPerCore.length);
        if (!Neural.countsEqual(counts, root.layerCounts)) {
            root.layerCounts = counts;
            root.meshLayout = Neural.layout(counts);
        }
    }

    // === per-tick intensity (separate from topology, see above) ===
    property var nodeIntensities: []
    property var edgeIntensities: []

    // === pulses (fast tier) ===
    property var _pulseState: [] // internal: [{edgeIndex, t}]
    property real _pulseSpawnAccum: 0
    property var pulses: [] // published: [{x,y}], read by NeuralPulses.qml

    readonly property bool critical: SystemStats.tempCritical || SystemStats.batteryCritical
    readonly property string stateChip: SystemStats.netOnline ? "[ SIGNAL ]" : "[ SILENT ]"
    readonly property var _peakCore: Neural.argmax(SystemStats.cpuPerCore)

    Timer {
        id: fastTimer
        interval: root.shedding ? 125 : 42 // ~8Hz shed / ~24Hz normal
        running: root.shouldAnimate
        repeat: true
        onTriggered: root.tickFast()
    }

    function tickFast() {
        const dt = fastTimer.interval / 1000;
        const sweepSeconds = Neural.SWEEP_SECONDS_IDLE -
            (Neural.SWEEP_SECONDS_IDLE - Neural.SWEEP_SECONDS_PEGGED) * (root.smoothedCpuAvg / 100);
        root.totalSweeps += dt / sweepSeconds;

        root._advancePulses(dt);
    }

    function _advancePulses(dt) {
        const edges = root.meshLayout.edges;
        if (edges.length === 0) {
            root.pulses = [];
            return;
        }

        const netBps = SystemStats.netRxBps + SystemStats.netTxBps;
        const speed = Neural.pulseSpeed(netBps);

        const next = [];
        for (const p of root._pulseState) {
            const t = p.t + speed * dt;
            if (t < 1)
                next.push({ edgeIndex: p.edgeIndex, t: t });
        }
        root._pulseState = next;

        // Offline: stop spawning entirely (in-flight pulses finish their
        // current edge) -- a clearer "no signal" tell than just dimming.
        if (SystemStats.netOnline) {
            const rate = Neural.pulseSpawnRate(netBps);
            root._pulseSpawnAccum += rate * dt;
            while (root._pulseSpawnAccum >= 1 && root._pulseState.length < Neural.MAX_PULSES) {
                root._pulseSpawnAccum -= 1;
                root._pulseState.push({ edgeIndex: Math.floor(Math.random() * edges.length), t: 0 });
            }
        } else {
            root._pulseSpawnAccum = 0;
        }

        root.pulses = root._pulseState.map(p => Neural.pulsePoint(edges[p.edgeIndex], p.t));
    }

    Timer {
        id: slowTimer
        interval: root.shedding ? 1000 : 333 // ~1Hz shed / ~3Hz normal
        running: root.shouldAnimate
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tickSlow()
    }

    function tickSlow() {
        root._maybeRelayout();
        const avgFrac = root.smoothedCpuAvg / 100;
        const numLayers = root.layerCounts.length;
        root.nodeIntensities = root.meshLayout.nodes.map(n =>
            Neural.nodeIntensity(n.layer, numLayers, root.sweepPos,
                n.layer === 0 ? (SystemStats.cpuPerCore[n.coreIndex] ?? 0) / 100 : 0,
                avgFrac));
        root.edgeIntensities = root.meshLayout.edges.map(e =>
            Neural.edgeIntensity(e.fromLayer, e.toLayer, numLayers, root.sweepPos, avgFrac));
    }

    // === HUD model ===
    readonly property var hudModel: [
        { x: 96, y: 84, size: 11, ls: 0.12, color: root.cMark,
          text: `ULTRAVIOLET // NEURAL · ${SystemStats.hostname.toUpperCase()}` },
        { x: 96, y: 130, size: 40, color: root.cValue,
          text: ((SystemStats.netRxBps + SystemStats.netTxBps) / 1024).toFixed(1) },
        { x: 96, y: 178, size: 13, color: root.cLine,
          text: "Signal throughput, KB/s" },
        { x: 96, y: 230, size: 13, ls: 0.12, color: root.cLine, text: "CORES" },
        { x: 96, y: 230, w: 280, align: "right", size: 13, color: root.cValue,
          text: `${root.layerCounts[0] ?? 0}/${SystemStats.cpuCount} MAPPED` },
        { x: 96, y: 258, size: 13, ls: 0.12, color: root.cLine, text: "PEAK" },
        { x: 96, y: 258, w: 280, align: "right", size: 13, color: root.cValue,
          text: `CORE ${root._peakCore.index} · ${root._peakCore.value.toFixed(0)}%` },
        { x: 96, y: 286, size: 13, ls: 0.12, color: root.cLine, text: "AVG LOAD" },
        { x: 96, y: 286, w: 280, align: "right", size: 13, color: root.cValue,
          text: `${SystemStats.cpuPercent.toFixed(1)}%` },
        { x: 96, y: 314, size: 13, ls: 0.12, color: root.cLine, text: "TEMP" },
        { x: 96, y: 314, w: 280, align: "right", size: 13, color: root.cValue,
          text: `${Math.round(SystemStats.tempC)}°C` },
        // AutoText renders this entry as rich text for the two-tone chip.
        { x: 96, y: 700, size: 13, color: root.cValue,
          text: `PHASE L${(1 + root.sweepPos * 3).toFixed(1)}/4 // ${SystemStats.hostname.toUpperCase()} · UP ${SystemStats.uptimeText} // ` +
                `<span style="color:${(root.critical ? root.cCrit : root.cLive).toString()}">${root.stateChip}</span>` },
        { x: 1244, y: 96, size: 11, ls: 0.12, rotate: 90, color: root.cFaint,
          text: `ROOT ${SystemStats.rootFreeGiB.toFixed(0)} GIB FREE · BAT ${Math.round(SystemStats.batteryPercent)}% · ${SystemStats.netIface.toUpperCase()}` },
        { x: 1042, y: 657, w: 130, align: "right", size: 11, ls: 0.12, color: root.cMark,
          text: `EPOCH · ${String(root.epoch).padStart(4, "0")}` },
        // Static column labels.
        { x: Neural.MESH_BBOX.x + Neural.LAYER_X[0] - 15, y: Neural.MESH_BBOX.y - 22, size: 10, ls: 0.08, color: root.cFaint, text: "INPUT" },
        { x: Neural.MESH_BBOX.x + Neural.LAYER_X[1] - 8, y: Neural.MESH_BBOX.y - 22, size: 10, ls: 0.08, color: root.cFaint, text: "H1" },
        { x: Neural.MESH_BBOX.x + Neural.LAYER_X[2] - 8, y: Neural.MESH_BBOX.y - 22, size: 10, ls: 0.08, color: root.cFaint, text: "H2" },
        { x: Neural.MESH_BBOX.x + Neural.LAYER_X[3] - 18, y: Neural.MESH_BBOX.y - 22, size: 10, ls: 0.08, color: root.cFaint, text: "OUTPUT" },
    ]

    // === layers, back to front ===

    // Static on purpose: a drifting grid read as too much background motion.
    OrbitalGrid {
        designScale: root.designScale
        cFaint: root.cFaint
    }

    NeuralMesh {
        designScale: root.designScale
        cLine: root.cLine
        cMark: root.cMark
        nodes: root.meshLayout.nodes
        edges: root.meshLayout.edges
        nodeIntensities: root.nodeIntensities
        edgeIntensities: root.edgeIntensities
    }

    NeuralPulses {
        designScale: root.designScale
        cLine: root.cLine
        cLive: root.cLive
        cCrit: root.cCrit
        pulses: root.pulses
        critical: root.critical
    }

    OrbitalHud {
        visible: root.showHud
        designScale: root.designScale
        cFaint: root.cFaint
        model: root.hudModel
    }
}
