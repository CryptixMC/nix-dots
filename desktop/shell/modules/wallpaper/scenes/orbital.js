.pragma library

// Orbital projection math ported from the design mockup; Orbital.qml drives
// theta/spin from real CPU load. Magic constants encode the mockup's framing.
//
// Sphere points are in object space and need toView() before scr(); orbitView()
// already returns view space. Mixing these up yields a wrongly-tilted curve.

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

// Sample counts reduced from the mockup; each stays sub-pixel at 2x scale.
var MERIDIAN_SAMPLES = 96; // 97 points
var GROUND_TRACK_SAMPLES = 288; // 289 points
var LEAD_ARC_SAMPLES = 32; // 33 points
var LIVE_ORBIT_SAMPLES = 96; // 97 points

// Bisection rounds at each visibility transition, so reduced sampling still
// gives a clean occlusion edge.
var BISECT_ITERS = 6;

// Fixed pool capacities for per-tick curve arrays (each closed curve has at most
// 2 visible + 2 hidden runs). QML uses fixed-length Instantiator models indexed into
// padded arrays, because recreating ShapePaths on length changes caused flashes.
var MERIDIAN_VIS_CAP = 20;
var MERIDIAN_HID_CAP = 20;
var GROUND_TRACK_CAP = 4;
var LIVE_ORBIT_VIS_CAP = 4;
var LIVE_ORBIT_HID_CAP = 4;
var LEAD_ARC_CAP = 4;

// Pads arr to n entries with null; null slots render nothing but keep the
// Instantiator model length constant.
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

// View-space point on the orbit circle (radius defaults to R_ORB); do not
// pass through toView().
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

// Ray-sphere test: is view-space point p hidden behind the planet? For orbit-plane
// geometry; sphere-surface points use surfaceVisible() instead.
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

// Is a toView()'d sphere-surface point on the camera-facing side?
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

// Samples pointFn over [t0,t1] in n steps, splits the projected polyline into
// visible/hidden runs by visFn, and bisects each transition so runs meet exactly.
// Returns {visible: [[x,y,...], ...], hidden: [...]}.
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

// The 9 meridians: front runs (op 0.75 every 60deg, else 0.5) and back runs
// (caller draws them dashed at a flat 0.4).
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

// Ground track just above the surface, shifted by the ascending node;
// camera-facing runs only.
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

// Lead arc ahead of the satellite, visible runs only. Must use the same radius
// as satelliteState() so it lies on the actual orbit.
function leadArc(theta, radius) {
    var pointFn = function (u) {
        return orbitView(theta + LEAD_ARC * u, radius);
    };
    return sampleBoth(pointFn, function (p) { return !occluded(p); }, 0, 1, LEAD_ARC_SAMPLES).visible;
}

// The only drawn orbit ring, sharing its radius with the satellite and lead arc.
// Front runs drawn solid, back runs dashed.
function liveOrbitRing(radius) {
    var pointFn = function (th) {
        return orbitView(th, radius);
    };
    return sampleBoth(pointFn, function (p) { return !occluded(p); }, 0, 2 * Math.PI, LIVE_ORBIT_SAMPLES);
}

// Satellite position/orientation/scale and occlusion. radius must match
// liveOrbitRing() so the satellite flies the drawn ring.
function satelliteState(theta, radius) {
    var p = orbitView(theta, radius);
    var proj = scr(p);
    var X = proj[0], Y = proj[1], s = proj[3];
    var occ = occluded(p);
    var ang = (Math.atan2(CY - Y, CX - X) * 180) / Math.PI - 90;
    var k = 0.46 * s;
    return { X: X, Y: Y, ang: ang, k: k, occluded: occ, s: s };
}

// Follow-tag leader/label placement, with flip/clamp rules that keep the label
// on-canvas and clear of the satellite.
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

// Real sub-satellite lat/lon of the CPU-driven orbit, formatted for the HUD.
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
