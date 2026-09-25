.pragma library

// Orbital projection math, ported from the design mockup's DCLogic class
// (Animated.dc.html -- a design-tool export, see
// themes/ultraviolet-v2/README.md's Wallpaper section for provenance).
// The mockup re-derives all of this from a fake 0-24s loop clock; here
// Orbital.qml drives theta/spin/radius from real CPU/RAM instead, but the
// projection itself -- the tilted-sphere camera, the orbit basis, the
// ray-sphere occlusion test -- is unchanged from the source, including
// every magic constant (they encode one specific camera framing the
// mockup was composed around; there's no simpler equivalent form).
//
// Coordinate convention, preserved from the mockup: sphere points start
// in "object space" ([R*cos(th)*cos(lon), R*sin(th), R*cos(th)*sin(lon)])
// and need toView() (the camera tilt) before scr(); orbitView() already
// returns points in view space (Av/Bv are view-space basis vectors) so
// its output goes straight to scr()/occluded() with no toView() step.
// Mixing these up silently produces a correctly-shaped but wrongly-tilted
// curve, so every function below documents which space it expects.

// === constants (verbatim from the mockup; encode one specific framing) ===
var R = 138.75629759328498; // planet radius, view-space units
var R_ORB = 356.549889797468; // nominal (baked) orbit radius
var D = 660.744274253738; // perspective distance (camera to origin)
var CX = 852.171568223288; // projection center x, design px
var CY = 329.9626197430551; // projection center y, design px
var TILT = -0.3490658503988659; // camera tilt, radians
var AV = [0.5735764363510462, 0.0, -0.8191520442889918]; // orbit plane basis a
var BV = [-0.6710100716628343, 0.5735764363510462, -0.46984631039295427]; // orbit plane basis b
var SPIN_TOTAL = 0.3490658503988659; // planet rotation over one full lap (20deg)
var NODE_SHIFT = 1.5201162495033038; // ground-track ascending-node phase offset
var SAT_TH0 = 3.464478565208744; // satellite's orbit angle at phase 0
var LEAD_ARC = 0.9075712110370514; // angular span of the "about to fly" arc
var LABEL_W = 162; // follow-tag label width, design px
var GRID_PITCH = 24; // dot-grid pitch, design px

// Sample counts, reduced from the mockup's 241/961/121/(~700, baked) --
// each is sub-native-pixel sagitta at 2x device scale (see the plan's
// "Sample-count reductions" table). The mockup oversampled because the
// design tool didn't care; a live per-frame recompute does.
var MERIDIAN_SAMPLES = 96; // 97 points
var GROUND_TRACK_SAMPLES = 288; // 289 points
var LEAD_ARC_SAMPLES = 32; // 33 points
var LIVE_ORBIT_SAMPLES = 96; // 97 points

// Bisection iterations run at each visibility transition to place the
// terminator/occlusion edge exactly, rather than at the coarse sample --
// this is what buys the sample-count reduction above without a ragged
// edge. A sphere gives at most 2 transitions per closed curve.
var BISECT_ITERS = 6;

// Fixed pool capacities for the per-tick curve arrays (meridians, ground
// track, live orbit ring, lead arc). Each closed curve gives at most 2
// visible + 2 hidden runs (a sphere has at most 2 occlusion transitions),
// so 9 meridians -> at most 18 runs each side; padded to 20 for headroom.
// These exist so the QML side can hand each array to a FIXED-length
// Instantiator model (an int, never a changing array) and index into the
// padded array from each delegate -- the delegate objects are then
// created exactly once and never destroyed/recreated as run counts
// fluctuate near an occlusion transition, which is what caused the
// "glitching/turning white" flashes when Instantiator tore down and
// rebuilt ShapePaths on every array-length change.
var MERIDIAN_VIS_CAP = 20;
var MERIDIAN_HID_CAP = 20;
var GROUND_TRACK_CAP = 4;
var LIVE_ORBIT_VIS_CAP = 4;
var LIVE_ORBIT_HID_CAP = 4;
var LEAD_ARC_CAP = 4;

// Pads (or truncates, which should never happen given the caps above)
// arr to exactly n entries, filling with null. A null entry renders as
// nothing (empty PathPolyline, zero-alpha stroke) rather than being
// omitted, which is what keeps the Instantiator's model length constant.
function padArray(arr, n) {
    var out = new Array(n);
    for (var i = 0; i < n; i++)
        out[i] = i < arr.length ? arr[i] : null;
    return out;
}

function toView(p) {
    var x = p[0], y = p[1], z = p[2];
    var c = Math.cos(TILT), s = Math.sin(TILT);
    return [x, y * c - z * s, y * s + z * c];
}

function toWorld(p) {
    var x = p[0], y = p[1], z = p[2];
    var c = Math.cos(TILT), s = Math.sin(TILT);
    return [x, y * c + z * s, -y * s + z * c];
}

function spinWorld(p, a) {
    var c = Math.cos(a), s = Math.sin(a);
    return [p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c];
}

// Perspective projection: view-space point -> [screenX, screenY, z, scale].
function scr(p) {
    var s = D / (D - p[2]);
    return [CX + p[0] * s, CY - p[1] * s, p[2], s];
}

// View-space point on the orbit circle of the given radius (defaults to
// the nominal R_ORB) at angle th. Already in view space -- do not pass
// through toView().
function orbitView(th, r) {
    if (r === undefined || r === null)
        r = R_ORB;
    var c = Math.cos(th), s = Math.sin(th);
    return [
        r * (c * AV[0] + s * BV[0]),
        r * (c * AV[1] + s * BV[1]),
        r * (c * AV[2] + s * BV[2]),
    ];
}

// Ray-sphere test: is the view-space point p (on the far side, toward the
// camera at z=D) hidden behind the planet? Used for orbit-plane geometry
// (orbitView() output), not for sphere-surface points (those use
// surfaceVisible() instead -- occlusion by SELF vs. occlusion by the
// planet are different tests).
function occluded(p) {
    var dx = p[0], dy = p[1], dz = p[2] - D;
    var a = dx * dx + dy * dy + dz * dz;
    var b = 2 * D * dz;
    var c = D * D - R * R;
    var disc = b * b - 4 * a * c;
    if (disc <= 0)
        return false;
    var sq = Math.sqrt(disc);
    var t1 = (-b - sq) / (2 * a);
    var t2 = (-b + sq) / (2 * a);
    return (t1 > 1e-6 && t1 < 1 - 1e-6) || (t2 > 1e-6 && t2 < 1 - 1e-6);
}

// Is a sphere-surface point (already toView()'d) on the camera-facing
// side? The mockup's exact self-occlusion test for meridians/ground track.
function surfaceVisible(p) {
    return p[2] > (R * R) / D;
}

function pad(v, width) {
    var s = v.toFixed(3);
    while (s.length < width)
        s = "0" + s;
    return s;
}

function toPoints(flat) {
    var out = [];
    for (var i = 0; i < flat.length; i += 2)
        out.push(Qt.point(flat[i], flat[i + 1]));
    return out;
}

// Samples pointFn(t) for t across [t0,t1] in n steps, splitting the
// projected polyline into visible/hidden runs by visFn(viewPoint). Each
// point is evaluated once; visibility transitions are then bisected
// (BISECT_ITERS rounds) directly against visFn/pointFn to place the
// crossing exactly, and the refined point is pushed onto BOTH runs so
// each terminates/starts exactly at the boundary. Returns
// {visible: [[x,y,x,y,...], ...], hidden: [[x,y,...], ...]} -- arrays of
// flat point-runs, one array per visible/hidden arc.
function sampleBoth(pointFn, visFn, t0, t1, n) {
    var n1 = n + 1;
    var sx = new Array(n1), sy = new Array(n1), sv = new Array(n1), st = new Array(n1);
    for (var k = 0; k < n1; k++) {
        var t = t0 + (t1 - t0) * k / n;
        var p = pointFn(t);
        var proj = scr(p);
        sx[k] = proj[0];
        sy[k] = proj[1];
        sv[k] = visFn(p);
        st[k] = t;
    }

    var px = [], py = [], pv = [];
    for (k = 0; k < n1; k++) {
        px.push(sx[k]);
        py.push(sy[k]);
        pv.push(sv[k]);
        if (k < n && sv[k] !== sv[k + 1]) {
            var lo = st[k], hi = st[k + 1];
            var loVis = sv[k];
            for (var iter = 0; iter < BISECT_ITERS; iter++) {
                var mid = (lo + hi) / 2;
                if (visFn(pointFn(mid)) === loVis)
                    lo = mid;
                else
                    hi = mid;
            }
            var bp = scr(pointFn((lo + hi) / 2));
            px.push(bp[0]); py.push(bp[1]); pv.push(sv[k]);     // closes the current run
            px.push(bp[0]); py.push(bp[1]); pv.push(sv[k + 1]); // opens the next run
        }
    }

    return { visible: splitRuns(px, py, pv, true), hidden: splitRuns(px, py, pv, false) };
}

function splitRuns(px, py, pv, want) {
    var out = [], cur = [];
    for (var i = 0; i < pv.length; i++) {
        if (pv[i] === want) {
            cur.push(px[i], py[i]);
        } else if (cur.length >= 4) {
            out.push(cur);
            cur = [];
        } else {
            cur = [];
        }
    }
    if (cur.length >= 4)
        out.push(cur);
    return out;
}

// The 9 meridians (lonDeg 0,20,...,160), each split into the
// camera-facing run (op varies: 0.75 for the 3 "major" meridians at
// lonDeg%60===0, else 0.5) and the far-side run (fixed dash, drawn at a
// flat 0.4 opacity by the caller -- matches the mockup's meridianHidden
// template, which has no per-segment op).
function meridians(spin) {
    var visible = [], hidden = [];
    for (var lonDeg = 0; lonDeg < 180; lonDeg += 20) {
        var lon = (lonDeg * Math.PI) / 180 + spin;
        (function (lon, op) {
            var pointFn = function (th) {
                return toView([R * Math.cos(th) * Math.cos(lon), R * Math.sin(th), R * Math.cos(th) * Math.sin(lon)]);
            };
            var res = sampleBoth(pointFn, surfaceVisible, 0, 2 * Math.PI, MERIDIAN_SAMPLES);
            for (var i = 0; i < res.visible.length; i++)
                visible.push({ op: op, pts: res.visible[i] });
            for (i = 0; i < res.hidden.length; i++)
                hidden.push(res.hidden[i]);
        })(lon, lonDeg % 60 === 0 ? 0.75 : 0.5);
    }
    return { visible: visible, hidden: hidden };
}

// The "next rev" ground track: a ring at ~R*1.004 (just above the
// surface) rotated by the ascending-node shift, camera-facing runs only
// (matches the mockup -- no hidden counterpart is drawn for this curve).
function groundTrack(spin) {
    var shift = NODE_SHIFT + spin;
    var pointFn = function (th) {
        var pw = toWorld(orbitView(th));
        var n = Math.sqrt(pw[0] * pw[0] + pw[1] * pw[1] + pw[2] * pw[2]);
        pw = spinWorld(pw, shift);
        var nn = Math.sqrt(pw[0] * pw[0] + pw[1] * pw[1] + pw[2] * pw[2]);
        return toView([pw[0] * R * 1.004 / nn, pw[1] * R * 1.004 / nn, pw[2] * R * 1.004 / nn]);
    };
    return sampleBoth(pointFn, surfaceVisible, 0, 2 * Math.PI, GROUND_TRACK_SAMPLES).visible;
}

// The "about to fly" lead arc ahead of the satellite -- camera-facing
// (non-occluded) runs only, drawn in the live-glow white. Takes the same
// radius as satelliteState() so the arc always lies exactly on the
// satellite's actual (memory-driven) orbit, never a stale fixed one.
function leadArc(theta, radius) {
    var pointFn = function (u) {
        return orbitView(theta + LEAD_ARC * u, radius);
    };
    return sampleBoth(pointFn, function (p) { return !occluded(p); }, 0, 1, LEAD_ARC_SAMPLES).visible;
}

// The orbit ring at the current (memory-driven) radius -- the ONLY orbit
// ring drawn; the satellite (satelliteState()) and its lead arc
// (leadArc()) take this same radius, so what's on screen always matches
// what the satellite is actually flying. Split into front (visible) and
// back (occluded) runs -- draw front solid, back dashed.
function liveOrbitRing(radius) {
    var pointFn = function (th) {
        return orbitView(th, radius);
    };
    return sampleBoth(pointFn, function (p) { return !occluded(p); }, 0, 2 * Math.PI, LIVE_ORBIT_SAMPLES);
}

// Satellite screen position/orientation/scale at orbit angle theta and
// radius, plus whether it's currently occluded by the planet. radius
// must be the same live (memory-driven) value passed to liveOrbitRing()
// -- this is what actually makes the satellite fly the ring that's
// drawn, rather than a separate fixed-radius path underneath it.
function satelliteState(theta, radius) {
    var p = orbitView(theta, radius);
    var proj = scr(p);
    var X = proj[0], Y = proj[1], s = proj[3];
    var occ = occluded(p);
    var ang = (Math.atan2(CY - Y, CX - X) * 180) / Math.PI - 90;
    var k = 0.46 * s;
    return { X: X, Y: Y, ang: ang, k: k, occluded: occ, s: s };
}

// Follow-tag ("SAT UV-1 ...") leader/label placement, mirroring the
// mockup's flip/clamp rules so the label stays on-canvas and doesn't
// overlap the satellite body.
function tagPlacement(X, Y, ang, k) {
    var angRad = (ang * Math.PI) / 180;
    var rad = 76 * k;
    var offx = rad + 30;
    var offy = 30 * k + 30;
    var flip = X + offx + LABEL_W > 1176;
    var ly = Y + offy;
    if (ly > 660 || (ly > 616 && X > 940))
        ly = Y - offy;
    ly = Math.min(Math.max(ly, 118), 686);
    var lx = flip ? X - offx : X + offx + LABEL_W;
    var anchorX = lx - LABEL_W;

    var tips = [[-76, -5.5], [76, -5.5]].map(function (t) {
        var a = t[0], b = t[1];
        return [
            X + k * (a * Math.cos(angRad) - b * Math.sin(angRad)),
            Y + k * (a * Math.sin(angRad) + b * Math.cos(angRad)),
        ];
    });
    var tip = tips[0];
    var bestD = Math.hypot(tip[0] - anchorX, tip[1] - ly);
    for (var i = 1; i < tips.length; i++) {
        var d = Math.hypot(tips[i][0] - anchorX, tips[i][1] - ly);
        if (d < bestD) { bestD = d; tip = tips[i]; }
    }
    var rx0 = lx - LABEL_W;
    return {
        px: tip[0], py: tip[1], mx: (tip[0] + lx) / 2, my: ly,
        lx: lx, ly: ly, rx0: rx0, rx1: rx0 + LABEL_W,
        labelLeft: rx0, labelTop: ly - 19,
    };
}

// Real (not invented) sub-satellite lat/lon, formatted like the mockup's
// pad()'d readout -- this is a genuine computed subpoint of a real,
// CPU-driven orbit, so it stays in the HUD as-is (see plan section 4).
function subpoint(theta, spin) {
    var p = orbitView(theta);
    var pw = toWorld(p);
    var n = Math.sqrt(pw[0] * pw[0] + pw[1] * pw[1] + pw[2] * pw[2]);
    var lat = (Math.asin(pw[1] / n) * 180) / Math.PI;
    var lon = (Math.atan2(pw[2], pw[0]) * 180) / Math.PI - (spin * 180) / Math.PI;
    lon = (((lon + 180) % 360) + 360) % 360 - 180;
    return {
        lat: lat, lon: lon,
        text: pad(Math.abs(lat), 6) + (lat >= 0 ? " N" : " S") + " / " + pad(Math.abs(lon), 7) + (lon >= 0 ? " E" : " W"),
    };
}
