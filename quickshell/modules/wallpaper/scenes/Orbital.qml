pragma ComponentBehavior: Bound
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Effects
import "../../../theme"
import "../../../services"
import "orbital.js" as Orbital
import "scene-palette.js" as ScenePalette

// The ultraviolet-v2 wallpaper scene ("engine": "scene", "scene": "Orbital"
// in theme.json) -- a live port of the design mockup's orbital HUD
// (Animated.dc.html), driven by real system metrics instead of the
// mockup's fake 0-24s loop clock. See themes/ultraviolet-v2/README.md's
// Wallpaper section for the full readout mapping and the motion rules.
//
// This file owns: stage sizing/scale, palette derivation, SystemStats
// acquire/release, motion integration (theta/spin/orbit radius/grid
// drift) with CPU-load shedding, and composing the five render layers.
// It reads nothing from `wp.dir` -- all geometry here is code, not a
// theme asset -- so it is structurally immune to the wp.dir directory
// race documented in Wallpaper.qml/ThemeDefaults.qml.
Item {
    id: root

    // Set by Wallpaper.qml's Loader (mirrors the per-monitor pause the
    // shader engine already has via Hyprland.monitorFor(screen)).
    required property bool shouldAnimate

    // Defaults true (the desktop wallpaper's existing behaviour, unchanged)
    // -- LockView sets this false via WallpaperContent.showSceneHud. Design
    // intent already called for this split (ultraviolet-v2/README.md:
    // "desktop.html and lock.html use a variant with the stat block
    // dropped, since on a real screen that corner belongs to windows or
    // the clock") but nothing had actually wired it until the lock screen
    // needed it for real -- LockView's own left-column content occupies
    // exactly the same corner this HUD does.
    property bool showHud: true

    readonly property real designScale: Math.max(width / 1280, height / 800)

    // Hides the scene until Theme.color has resolved past ThemeLoader's
    // async fallback (see Theme.qml's `resolved` comment) -- painting even
    // one frame with the fallback's baseline role mapping (lineStrong =
    // base06, a near-white grey, where ultraviolet-v2's theme.json remaps
    // it to purple) is exactly the "white flash on the planet when it
    // first loads" this scene is meant to avoid. Opacity, not visible, so
    // children still construct/bind normally underneath and the reveal is
    // a smooth fade rather than a hard pop once resolved flips true.
    opacity: Theme.resolved ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

    // === palette ===
    // Derivation lives in scene-palette.js (shared with every other scene
    // under this directory) -- see that file for the measured-HSV-ramp
    // rationale and the catppuccin degradation note.
    // cCrit and cLive deliberately unused here -- the satellite/HUD used
    // to flip to cCrit (pink) whenever tempCritical/batteryCritical went
    // true (with no hysteresis on the 80C threshold, that flashed the
    // satellite between colours at random), and its normal-state colour
    // was cLive -- the theme's "live" role, which in ultraviolet-v2 is a
    // near-white base07, not purple. The scene now stays one consistent
    // colour, cLine (the actual purple accent line colour), always.
    readonly property var _palette: ScenePalette.derivePalette(Theme.color)
    readonly property color cLine: root._palette.cLine
    readonly property color cFaint: root._palette.cFaint
    readonly property color cMark: root._palette.cMark
    readonly property color cValue: root._palette.cValue

    // === SystemStats lifecycle ===
    // Acquired on shouldAnimate, not just component lifetime, so a
    // fullscreen window on THIS monitor stops /proc polling entirely
    // while a second monitor (still animating) keeps it alive via its own
    // acquire() -- SystemStats' refcount makes that correct without this
    // scene needing to know about other monitors.
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
    // The wallpaper's whole point is to display a CPU number -- if IT
    // becomes a meaningful CPU cost right when the machine is under load,
    // that's a feedback loop. Dropping the tick rate under sustained high
    // CPU is thematically invisible (the satellite is "supposed" to be
    // flying fast right when this kicks in) and yields CPU exactly when
    // needed. 5s sustained above/below the two thresholds, not instant,
    // so a brief spike doesn't flap the tick rate.
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
    // theta is INTEGRATED (theta += omega*dt) every fast tick, never
    // computed as t*omega -- otherwise a CPU spike that changes omega
    // would teleport the satellite instead of accelerating it.
    property real theta: Orbital.SAT_TH0
    property real smoothedCpu: SystemStats.cpuPercent
    Behavior on smoothedCpu { SmoothedAnimation { velocity: 25 } }

    // Laps completed since this scene started (fractional) -- both the
    // rev counter and the sawtooth spin term (the mockup resets its
    // globe-rotation term each lap; replicated here rather than let it
    // grow unbounded) come from this one value.
    readonly property real lapsCompleted: (root.theta - Orbital.SAT_TH0) / (2 * Math.PI)
    readonly property int revCount: 574 + Math.floor(root.lapsCompleted)
    readonly property real spin: Orbital.SPIN_TOTAL * (root.lapsCompleted - Math.floor(root.lapsCompleted))

    // Orbit radius is fixed at the nominal baked radius -- it used to
    // track free RAM (shrinking the ring as memory filled up), but that
    // meant the ring/satellite visibly resized on every memory
    // fluctuation, which read as glitchy rather than "alive". The
    // satellite's angular SPEED still tracks CPU (see tickFast() below);
    // that's the one live-motion channel that's supposed to be visible.
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

        // Both take root.liveOrbitRadius -- the same radius liveOrbitRing()
        // draws in tickSlow() below -- so the satellite and its lead arc
        // always fly exactly the ring that's on screen, not a separate
        // fixed-radius path underneath it.
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
        // Padded to a fixed capacity (see orbital.js's padArray comment) --
        // the Instantiators below use a constant-length int model keyed
        // off these caps, so ShapePath delegates are created once and
        // just have their bound entry swap under them each tick, instead
        // of being destroyed/recreated whenever a run count changes near
        // an occlusion transition (the "glitching/turning white" bug).
        const m = Orbital.meridians(root.spin);
        root.meridianVisible = Orbital.padArray(m.visible, Orbital.MERIDIAN_VIS_CAP);
        root.meridianHidden = Orbital.padArray(m.hidden, Orbital.MERIDIAN_HID_CAP);
        root.groundTrackRuns = Orbital.padArray(Orbital.groundTrack(root.spin), Orbital.GROUND_TRACK_CAP);
        const lo = Orbital.liveOrbitRing(root.liveOrbitRadius);
        root.liveOrbitVisible = Orbital.padArray(lo.visible, Orbital.LIVE_ORBIT_VIS_CAP);
        root.liveOrbitHidden = Orbital.padArray(lo.hidden, Orbital.LIVE_ORBIT_HID_CAP);
        root.subpointText = Orbital.subpoint(root.theta, root.spin).text;
    }

    // === HUD model (see the plan's readout mapping table) ===
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
        // AutoText (the delegate's default textFormat) sniffs the <span>
        // and renders this one richly for a two-tone chip -- every other
        // entry has no markup and renders as plain text as usual. The
        // chip's TEXT still varies with occlusion/link state; its colour
        // stays the one consistent purple (cLine), not a critical-driven flip.
        { x: 96, y: 700, size: 13, color: root.cValue,
          text: `SUBPOINT ${root.subpointText} // ${SystemStats.hostname.toUpperCase()} · UP ${SystemStats.uptimeText} // ` +
                `<span style="color:${root.cLine.toString()}">${root.stateChip}</span>` },
        { x: 1244, y: 96, size: 11, ls: 0.12, rotate: 90, color: root.cFaint,
          text: `ROOT ${SystemStats.rootFreeGiB.toFixed(0)} GIB FREE · BAT ${Math.round(SystemStats.batteryPercent)}% · ${SystemStats.netIface.toUpperCase()}` },
        { x: 1042, y: 657, w: 130, align: "right", size: 11, ls: 0.12, color: root.cMark,
          text: `ASC NODE · ${String(root.revCount).padStart(4, "0")}` },
    ]

    // === layers, back to front ===

    // Static -- offsetX/offsetY deliberately left at their 0 defaults.
    // The grid used to drift (originally network-throughput-driven, then
    // a fixed 2px/sec) and read as the background "moving too much"
    // either way. Painted once, never translated.
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

    // Live globe linework: meridians, ground track, and the ONE orbit
    // ring (at the current memory-driven radius, the same one the
    // satellite below actually flies) -- shares one glowing FBO (3Hz
    // repaint budget) matching the mockup's `hero-glow` group, which
    // wraps this content together with the static latitude rings/limb
    // OrbitalPlate already drew underneath (that pairing is why the two
    // use the SAME 24px/0.35 glow parameters).
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
            // Repeater-with-ShapePath-delegate logs "Delegate must be of
            // Item type" and produces nothing (confirmed against the real
            // quickshell binary) -- ShapePath isn't an Item. Instantiator
            // has no such restriction; each delegate is appended into
            // Shape.data (its default property, a plain
            // QQmlListProperty<QObject>) by hand instead.
            //
            // Every model below is a fixed integer (a pool capacity from
            // orbital.js), NOT the live array itself -- the live array is
            // read by index from inside the delegate. Since the model's
            // length never changes, Instantiator creates each ShapePath
            // exactly once at startup and never destroys/recreates it;
            // only the bound `entry` re-evaluates as root.meridianVisible
            // etc. are reassigned each slow tick. A null entry (padding,
            // or a currently-empty slot) draws as a zero-alpha, zero-point
            // path -- invisible without needing the delegate torn down.
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

    // Follow-tag label text ("SAT UV-1 · N% CPU") -- kept separate from
    // OrbitalHud's model (which only refreshes at SystemStats' ~1Hz pace)
    // because its POSITION must track the satellite every fast tick; a
    // plain Text with manually-scaled geometry stays crisp the same way
    // OrbitalHud's entries do; it just updates x/y at 24Hz instead of 1Hz.
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
