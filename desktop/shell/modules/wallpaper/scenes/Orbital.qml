pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Effects
import "../../../theme"
import "../../../services"
import "orbital.js" as Orbital
import "scene-palette.js" as ScenePalette

// Orbital HUD wallpaper scene: a live port of the design mockup driven by real
// system metrics. Owns stage scaling, palette, SystemStats acquire/release, motion
// with CPU-load shedding, and composing the render layers.
Item {
    id: root

    // Set by WallpaperContent.qml; false while this monitor has a fullscreen window.
    required property bool shouldAnimate

    // False on the lock screen, where the HUD would collide with LockView's content.
    property bool showHud: true

    readonly property real designScale: Math.max(width / 1280, height / 800)

    // Hidden until Theme.color resolves so fallback colours (near-white lineStrong)
    // never flash; opacity rather than visible so children still bind and it fades in.
    opacity: Theme.resolved ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

    // === palette ===
    // cLive/cCrit are intentionally unused: the scene stays one consistent accent
    // colour (flipping on critical without hysteresis flickered).
    readonly property var _palette: ScenePalette.derivePalette(Theme.color)
    readonly property color cLine: root._palette.cLine
    readonly property color cFaint: root._palette.cFaint
    readonly property color cMark: root._palette.cMark
    readonly property color cValue: root._palette.cValue

    // === SystemStats lifecycle ===
    // Tied to shouldAnimate so a fullscreen monitor stops polling; SystemStats is
    // refcounted, so other monitors keep it alive.
    onShouldAnimateChanged: {
        if (shouldAnimate)
            SystemStats.acquire();
        else
            SystemStats.release();
    }
    Component.onCompleted: {
        if (root.shouldAnimate)
            SystemStats.acquire();
    }
    Component.onDestruction: {
        if (root.shouldAnimate)
            SystemStats.release();
    }

    // === load shedding ===
    // Drop tick rates under sustained high CPU so the wallpaper never adds load when
    // it matters. 5s hysteresis keeps brief spikes from flapping the rate.
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

    // === motion state ===
    // Integrated per tick (not t*omega) so a CPU spike accelerates the satellite
    // instead of teleporting it.
    property real theta: Orbital.SAT_TH0
    property real smoothedCpu: SystemStats.cpuPercent
    Behavior on smoothedCpu { SmoothedAnimation { velocity: 25 } }

    // Fractional laps since start; drives the rev counter and the sawtooth spin
    // (reset each lap, as in the mockup, instead of growing unbounded).
    readonly property real lapsCompleted: (root.theta - Orbital.SAT_TH0) / (2 * Math.PI)
    readonly property int revCount: 574 + Math.floor(root.lapsCompleted)
    readonly property real spin: Orbital.SPIN_TOTAL * (root.lapsCompleted - Math.floor(root.lapsCompleted))

    // Fixed at the nominal radius: tracking RAM made the ring resize visibly and read
    // as glitchy. CPU still drives angular speed.
    readonly property real liveOrbitRadius: Orbital.R_ORB

    // === per-frame fast state (satellite, lead arc, follow tag) ===
    property real satX: 0
    property real satY: 0
    property real satAngle: 0
    property real satK: 1
    property bool satOccluded: false
    property var leadArcRuns: []
    property var tagState: null

    readonly property string stateChip: (root.satOccluded || !SystemStats.netOnline) ? "[ OCCULTED ]" : "[ TRACKING ]"
    readonly property real satDimOpacity: root.satOccluded ? 0 : (!SystemStats.netOnline ? 0.35 : 1)

    Timer {
        id: fastTimer
        interval: root.shedding ? 125 : 42 // ~8Hz shed / ~24Hz normal
        running: root.shouldAnimate
        repeat: true
        onTriggered: root.tickFast()
    }

    function tickFast() {
        const dt = fastTimer.interval / 1000;
        // Idle (0% CPU) -> 60s/lap, pegged (100%) -> 8s/lap.
        const lapSeconds = 60 - 52 * (root.smoothedCpu / 100);
        const omega = (2 * Math.PI) / lapSeconds;
        root.theta += omega * dt;

        // Same radius as liveOrbitRing() so the satellite flies the drawn ring.
        const sat = Orbital.satelliteState(root.theta, root.liveOrbitRadius);
        root.satX = sat.X;
        root.satY = sat.Y;
        root.satAngle = sat.ang;
        root.satK = sat.k;
        root.satOccluded = sat.occluded;
        root.leadArcRuns = Orbital.padArray(Orbital.leadArc(root.theta, root.liveOrbitRadius), Orbital.LEAD_ARC_CAP);
        root.tagState = Orbital.tagPlacement(sat.X, sat.Y, sat.ang, sat.k);
    }

    // === per-frame slow state (meridians, ground track, live orbit ring) ===
    property var meridianVisible: []
    property var meridianHidden: []
    property var groundTrackRuns: []
    property var liveOrbitVisible: []
    property var liveOrbitHidden: []
    property string subpointText: ""

    Timer {
        id: slowTimer
        interval: root.shedding ? 1000 : 333 // ~1Hz shed / ~3Hz normal
        running: root.shouldAnimate
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tickSlow()
    }

    function tickSlow() {
        // Padded to fixed capacity so ShapePath delegates are never recreated (see padArray).
        const m = Orbital.meridians(root.spin);
        root.meridianVisible = Orbital.padArray(m.visible, Orbital.MERIDIAN_VIS_CAP);
        root.meridianHidden = Orbital.padArray(m.hidden, Orbital.MERIDIAN_HID_CAP);
        root.groundTrackRuns = Orbital.padArray(Orbital.groundTrack(root.spin), Orbital.GROUND_TRACK_CAP);
        const lo = Orbital.liveOrbitRing(root.liveOrbitRadius);
        root.liveOrbitVisible = Orbital.padArray(lo.visible, Orbital.LIVE_ORBIT_VIS_CAP);
        root.liveOrbitHidden = Orbital.padArray(lo.hidden, Orbital.LIVE_ORBIT_HID_CAP);
        root.subpointText = Orbital.subpoint(root.theta, root.spin).text;
    }

    // === HUD model ===
    readonly property var hudModel: [
        { x: 96, y: 84, size: 11, ls: 0.12, color: root.cMark,
          text: `ULTRAVIOLET // ORBITAL · ${SystemStats.hostname.toUpperCase()}` },
        { x: 96, y: 130, size: 40, color: root.cValue,
          text: SystemStats.memUsedMiB.toFixed(1) },
        { x: 96, y: 178, size: 13, color: root.cLine,
          text: "Memory in use, MiB" },
        { x: 96, y: 230, size: 13, ls: 0.12, color: root.cLine, text: "CPU" },
        { x: 96, y: 230, w: 280, align: "right", size: 13, color: root.cValue,
          text: `${SystemStats.cpuPercent.toFixed(1)}%` },
        { x: 96, y: 258, size: 13, ls: 0.12, color: root.cLine, text: "TEMP" },
        { x: 96, y: 258, w: 280, align: "right", size: 13, color: root.cValue,
          text: `${Math.round(SystemStats.tempC)}°C` },
        { x: 96, y: 286, size: 13, ls: 0.12, color: root.cLine, text: "NET" },
        { x: 96, y: 286, w: 280, align: "right", size: 13, color: root.cValue,
          text: `↓${(SystemStats.netRxBps / 1e6).toFixed(2)} ↑${(SystemStats.netTxBps / 1e6).toFixed(2)} MB/s` },
        { x: 96, y: 314, size: 13, ls: 0.12, color: root.cLine, text: "LOAD" },
        { x: 96, y: 314, w: 280, align: "right", size: 13, color: root.cValue,
          text: `${SystemStats.load1.toFixed(2)} / ${SystemStats.cpuCount}` },
        // AutoText renders this entry as rich text for the two-tone chip.
        { x: 96, y: 700, size: 13, color: root.cValue,
          text: `SUBPOINT ${root.subpointText} // ${SystemStats.hostname.toUpperCase()} · UP ${SystemStats.uptimeText} // ` +
                `<span style="color:${root.cLine.toString()}">${root.stateChip}</span>` },
        { x: 1244, y: 96, size: 11, ls: 0.12, rotate: 90, color: root.cFaint,
          text: `ROOT ${SystemStats.rootFreeGiB.toFixed(0)} GIB FREE · BAT ${Math.round(SystemStats.batteryPercent)}% · ${SystemStats.netIface.toUpperCase()}` },
        { x: 1042, y: 657, w: 130, align: "right", size: 11, ls: 0.12, color: root.cMark,
          text: `ASC NODE · ${String(root.revCount).padStart(4, "0")}` },
    ]

    // === layers, back to front ===

    // Static on purpose: a drifting grid read as too much background motion.
    OrbitalGrid {
        designScale: root.designScale
        cFaint: root.cFaint
    }

    OrbitalPlate {
        designScale: root.designScale
        cLine: root.cLine
        cFaint: root.cFaint
        cMark: root.cMark
    }

    // Live globe linework (meridians, ground track, orbit ring) in one glowing layer,
    // using the same 24px/0.35 glow as OrbitalPlate's rings and limb.
    Item {
        id: globeLive
        width: 1280
        height: 800
        scale: root.designScale
        transformOrigin: Item.TopLeft

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, 0.35)
            shadowBlur: 0.6
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }

        Shape {
            id: globeShape
            anchors.fill: parent
            // Instantiator + manual Shape.data because a Repeater can't delegate a ShapePath.
            // Models are fixed pool capacities read by index, so delegates are created once;
            // null entries draw as invisible zero-point paths.
            Instantiator {
                model: Orbital.MERIDIAN_VIS_CAP
                delegate: ShapePath {
                    id: meridianVisPath
                    required property int index
                    readonly property var entry: root.meridianVisible[meridianVisPath.index] ?? null
                    strokeColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, meridianVisPath.entry ? meridianVisPath.entry.op : 0)
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathPolyline { path: meridianVisPath.entry ? Orbital.toPoints(meridianVisPath.entry.pts) : [] }
                }
                onObjectAdded: (index, object) => globeShape.data.push(object)
                onObjectRemoved: (index, object) => {
                    const i = globeShape.data.indexOf(object);
                    if (i >= 0) globeShape.data.splice(i, 1);
                }
            }
            Instantiator {
                model: Orbital.MERIDIAN_HID_CAP
                delegate: ShapePath {
                    id: meridianHidPath
                    required property int index
                    readonly property var entry: root.meridianHidden[meridianHidPath.index] ?? null
                    strokeColor: Qt.rgba(root.cFaint.r, root.cFaint.g, root.cFaint.b, meridianHidPath.entry ? 0.4 : 0)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 4]
                    fillColor: "transparent"
                    PathPolyline { path: meridianHidPath.entry ? Orbital.toPoints(meridianHidPath.entry) : [] }
                }
                onObjectAdded: (index, object) => globeShape.data.push(object)
                onObjectRemoved: (index, object) => {
                    const i = globeShape.data.indexOf(object);
                    if (i >= 0) globeShape.data.splice(i, 1);
                }
            }
            Instantiator {
                model: Orbital.GROUND_TRACK_CAP
                delegate: ShapePath {
                    id: groundTrackPath
                    required property int index
                    readonly property var entry: root.groundTrackRuns[groundTrackPath.index] ?? null
                    strokeColor: Qt.rgba(root.cFaint.r, root.cFaint.g, root.cFaint.b, groundTrackPath.entry ? 0.65 : 0)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [4, 5]
                    fillColor: "transparent"
                    PathPolyline { path: groundTrackPath.entry ? Orbital.toPoints(groundTrackPath.entry) : [] }
                }
                onObjectAdded: (index, object) => globeShape.data.push(object)
                onObjectRemoved: (index, object) => {
                    const i = globeShape.data.indexOf(object);
                    if (i >= 0) globeShape.data.splice(i, 1);
                }
            }
            Instantiator {
                model: Orbital.LIVE_ORBIT_VIS_CAP
                delegate: ShapePath {
                    id: liveOrbitVisPath
                    required property int index
                    readonly property var entry: root.liveOrbitVisible[liveOrbitVisPath.index] ?? null
                    strokeColor: Qt.rgba(root.cLine.r, root.cLine.g, root.cLine.b, liveOrbitVisPath.entry ? 0.9 : 0)
                    strokeWidth: 1
                    fillColor: "transparent"
                    PathPolyline { path: liveOrbitVisPath.entry ? Orbital.toPoints(liveOrbitVisPath.entry) : [] }
                }
                onObjectAdded: (index, object) => globeShape.data.push(object)
                onObjectRemoved: (index, object) => {
                    const i = globeShape.data.indexOf(object);
                    if (i >= 0) globeShape.data.splice(i, 1);
                }
            }
            Instantiator {
                model: Orbital.LIVE_ORBIT_HID_CAP
                delegate: ShapePath {
                    id: liveOrbitHidPath
                    required property int index
                    readonly property var entry: root.liveOrbitHidden[liveOrbitHidPath.index] ?? null
                    strokeColor: Qt.rgba(root.cFaint.r, root.cFaint.g, root.cFaint.b, liveOrbitHidPath.entry ? 0.5 : 0)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [3, 5]
                    fillColor: "transparent"
                    PathPolyline { path: liveOrbitHidPath.entry ? Orbital.toPoints(liveOrbitHidPath.entry) : [] }
                }
                onObjectAdded: (index, object) => globeShape.data.push(object)
                onObjectRemoved: (index, object) => {
                    const i = globeShape.data.indexOf(object);
                    if (i >= 0) globeShape.data.splice(i, 1);
                }
            }
        }
    }

    OrbitalSat {
        designScale: root.designScale
        cLine: root.cLine
        satX: root.satX
        satY: root.satY
        satAngle: root.satAngle
        satK: root.satK
        satDimOpacity: root.satDimOpacity
        leadArcRuns: root.leadArcRuns
        tag: root.tagState
    }

    // Kept out of OrbitalHud because its position tracks the satellite every fast tick.
    Text {
        id: satTagLabel
        visible: root.tagState !== null
        opacity: root.satDimOpacity
        text: `SAT UV-1 · ${Math.round(SystemStats.cpuPercent)}% CPU`
        color: root.cLine
        font.family: Theme.font.family
        font.pixelSize: 11 * root.designScale
        font.letterSpacing: 0.12 * 11 * root.designScale
        renderType: Text.NativeRendering
        x: root.tagState ? (root.tagState.labelLeft + 162) * root.designScale - width : 0
        y: root.tagState ? root.tagState.labelTop * root.designScale : 0
    }

    OrbitalHud {
        visible: root.showHud
        designScale: root.designScale
        cFaint: root.cFaint
        model: root.hudModel
    }
}
