.pragma library

// Neural-network wallpaper math/data, mirroring orbital.js's shape:
// constants, pure functions, no state. See themes/ultraviolet-v2's
// (or wherever this scene is documented) Wallpaper section for the full
// metric-to-channel map. Unlike orbital.js's constants (ported from a
// design mockup), everything here is an original layout -- tunable.

// === topology ===
var INPUT_CAP = 16; // caps the input layer at this host's real core count
                     // on the dev machine this shipped on; a higher-core
                     // host is truncated, not averaged -- the truncation
                     // is disclosed on the HUD's CORES row, never hidden.
var HIDDEN_SIZES = [6, 4];
var OUTPUT_SIZE = 3;

// === layout, local coordinates within the mesh's own bounding box ===
// (NeuralMesh.qml positions/sizes its glow wrapper Item to this box
// within the 1280x800 stage, so the MultiEffect FBO only covers content
// that actually needs blurring, not the full stage.)
var MESH_BBOX = { x: 450, y: 140, w: 660, h: 500 };
var LAYER_X = [30, 250, 450, 630]; // 4 columns, local to MESH_BBOX
var Y_TOP = 20, Y_BOTTOM = 460; // local vertical span
var NODE_R = 6; // design px

// === activation wave ===
var WAVE_SIGMA = 0.22; // gaussian half-width of the traveling activation
                        // bump, in normalized [0,1] layer-position units
                        // (4 layers -> 0.333 spacing, so this overlaps
                        // 1-2 adjacent layers -- a cascade, not a single
                        // hard column jumping between layers)
var SWEEP_SECONDS_IDLE = 4.0; // 0% CPU avg -> one L->R sweep per 4s
var SWEEP_SECONDS_PEGGED = 1.2; // 100% CPU avg -> one sweep per 1.2s
                                 // (not lower -- the mesh only redraws at
                                 // ~3Hz, and going much faster than this
                                 // starts under-sampling the sweep)

// === pulses (the satellite analog -- the fast-tier, literally-moving
// glowing thing) ===
var MAX_PULSES = 40;

function layerCounts(realCoreCount) {
    return [
        Math.max(1, Math.min(realCoreCount, INPUT_CAP)),
        HIDDEN_SIZES[0],
        HIDDEN_SIZES[1],
        OUTPUT_SIZE,
    ];
}

// Static topology. Node/edge x,y never change after this; only their
// displayed intensity does (see nodeIntensity()/edgeIntensity() below).
// Layer-0 nodes carry coreIndex = their position within that layer,
// which equals the real core index by construction (cores are laid out
// in order 0..n-1).
function layout(counts) {
    const nodes = [], edges = [], byLayer = [];
    for (let L = 0; L < counts.length; L++) {
        const n = counts[L], idxs = [];
        for (let i = 0; i < n; i++) {
            const y = n > 1 ? Y_TOP + (Y_BOTTOM - Y_TOP) * i / (n - 1) : (Y_TOP + Y_BOTTOM) / 2;
            idxs.push(nodes.length);
            const node = { layer: L, x: LAYER_X[L], y: y };
            if (L === 0)
                node.coreIndex = i;
            nodes.push(node);
        }
        byLayer.push(idxs);
    }
    for (let L2 = 0; L2 < counts.length - 1; L2++) {
        for (const a of byLayer[L2]) {
            for (const b of byLayer[L2 + 1]) {
                edges.push({
                    fromLayer: L2, toLayer: L2 + 1,
                    x1: nodes[a].x, y1: nodes[a].y,
                    x2: nodes[b].x, y2: nodes[b].y,
                });
            }
        }
    }
    return { nodes: nodes, edges: edges };
}

// True if the layer-count PATTERN differs (element-wise) -- used by
// NeuralNet.qml to decide whether to rebuild (and reassign, to the
// Repeater/Instantiator models) the topology at all. In practice this
// only ever flips once, very early (cpuPerCore.length going from 0 to a
// real count on the first successful /proc/stat poll) -- comparing by
// value here, not relying on object identity, is what lets the caller
// avoid reassigning (and so churning) the topology every tick just
// because SystemStats.cpuPerCore was reassigned to an equal-shaped array.
function countsEqual(a, b) {
    if (!a || !b || a.length !== b.length)
        return false;
    for (let i = 0; i < a.length; i++)
        if (a[i] !== b[i])
            return false;
    return true;
}

function circularDist(a, b) {
    const d = Math.abs(a - b) % 1;
    return Math.min(d, 1 - d);
}
function waveValue(normPos, sweepPos) {
    const d = circularDist(normPos, sweepPos);
    return Math.exp(-(d * d) / (2 * WAVE_SIGMA * WAVE_SIGMA));
}

// coreFrac (0..1) is the REAL per-core load for layer-0 nodes; ignored
// for layer>0. cpuAvgFrac must be the SAME smoothed value that drove
// sweepPos this tick -- one source of truth per tick, no independently
// recomputed approximation (this is the exact bug class that shipped a
// disconnected orbit ring in the Orbital scene; see that scene's README).
function nodeIntensity(layerIndex, numLayers, sweepPos, coreFrac, cpuAvgFrac) {
    const wave = waveValue(layerIndex / (numLayers - 1), sweepPos);
    if (layerIndex === 0)
        return Math.min(1, coreFrac * (0.55 + 0.45 * wave));
    return wave * (0.3 + 0.7 * cpuAvgFrac);
}
function edgeIntensity(fromLayer, toLayer, numLayers, sweepPos, cpuAvgFrac) {
    const a = waveValue(fromLayer / (numLayers - 1), sweepPos);
    const b = waveValue(toLayer / (numLayers - 1), sweepPos);
    return Math.max(a, b) * (0.3 + 0.7 * cpuAvgFrac);
}

function pulseSpawnRate(netBps) {
    return 0.4 + Math.min(11.6, netBps / (170 * 1024)); // 0.4-12/sec
}
function pulseSpeed(netBps) {
    return 0.6 + Math.min(2.5, netBps / (200 * 1024)); // 0.6-3.1 edges/sec
}
function pulsePoint(edge, t) {
    return { x: edge.x1 + (edge.x2 - edge.x1) * t, y: edge.y1 + (edge.y2 - edge.y1) * t };
}

function argmax(arr) {
    let bi = 0, bv = -1;
    for (let i = 0; i < arr.length; i++) {
        if (arr[i] > bv) {
            bv = arr[i];
            bi = i;
        }
    }
    return { index: bi, value: bv };
}
