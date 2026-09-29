.pragma library

// Shared accent-ramp derivation for scenes. A .pragma library can't see QML
// singletons, so callers pass Theme.color explicitly.

// Theme.color roles may be plain "#rrggbb" strings, and JS params get no color
// coercion: Qt.hsva() on a string silently yields transparent black.
// Tinting with a fully transparent color is a no-op that forces a real color.
function toColor(v) {
    return Qt.tint(v, "#00000000");
}

// Desaturates at constant HSV value, derived from lineStrong so the ramp stays
// coherent on multi-hue palettes instead of using hardcoded hexes.
// unrelated green/yellow smear on top of it.
function rampStep(c, k) {
    return Qt.hsva(c.hsvHue, c.hsvSaturation * k, c.hsvValue, c.a);
}

// cMark/cValue are the 2nd/3rd accent-ramp rungs (no design role exists for them);
// k1/k2 default to the ultraviolet-v2 ramp steps.
function derivePalette(themeColor, k1, k2) {
    if (k1 === undefined)
        k1 = 0.96;
    if (k2 === undefined)
        k2 = 0.88;
    const cLine = toColor(themeColor.lineStrong);
    return {
        cLine: cLine,
        cFaint: toColor(themeColor.dot),
        cLive: toColor(themeColor.live),
        cCrit: toColor(themeColor.critical),
        cMark: rampStep(cLine, k1), // ~#c050ff on v2
        cValue: rampStep(cLine, k2), // ~#d35cf7 on v2
    };
}
