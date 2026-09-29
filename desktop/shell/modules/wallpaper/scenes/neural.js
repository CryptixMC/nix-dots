.pragma library

// Neural-network wallpaper constants and pure functions, no state.
// The layout is original (not from a mockup), so values are freely tunable.

// === topology ===
var INPUT_CAP = 16; // higher core counts are truncated (disclosed on the HUD's CORES row)
var HIDDEN_SIZES = [6, 4];
var OUTPUT_SIZE = 3;

// === layout, local coordinates within the mesh's own bounding box ===
// NeuralMesh.qml sizes its glow to this box so the blur skips empty stage.
var MESH_BBOX = { x: 450, y: 140, w: 660, h: 500 };
var LAYER_X = [30, 250, 450, 630]; // 4 columns, local to MESH_BBOX
var Y_TOP = 20, Y_BOTTOM = 460; // local vertical span
var NODE_R = 6; // design px

// === activation wave ===
var WAVE_SIGMA = 0.22; // gaussian half-width, in normalized layer-position units
var SWEEP_SECONDS_IDLE = 4.0; // 0% CPU avg -> one L->R sweep per 4s
var SWEEP_SECONDS_PEGGED = 1.2; // 100% CPU avg -> one sweep per 1.2s; faster under-samples the ~3Hz mesh

// === pulses ===
var MAX_PULSES = 40;

function layerCounts(realCoreCount) {
    return [
        Math.max(1, Math.min(realCoreCount, INPUT_CAP)),
        HIDDEN_SIZES[0],
        HIDDEN_SIZES[1],
        OUTPUT_SIZE,
    ];
}

// Static topology; only intensities change afterwards. Layer-0 coreIndex equals
// the real core index.
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

// Compared by value so the caller rebuilds topology only when layer counts
// actually change, not every time cpuPerCore is reassigned.
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

// coreFrac is the real per-core load (layer 0 only). cpuAvgFrac must be the same
// smoothed value that drove sweepPos this tick, not a recomputed approximation.
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
