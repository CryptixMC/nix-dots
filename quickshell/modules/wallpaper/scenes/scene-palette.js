.pragma library

// Shared accent-ramp derivation for every scene under this directory.
// A .pragma library script has no implicit access to QML singletons the
// way a .qml file's `import "../../../theme"` does -- confirmed by this
// directory's other .pragma library files (orbital.js, neural.js), none
// of which import a QML type; they only use JS-engine globals (Qt.point,
// Qt.hsva) that are available regardless of import context. derivePalette()
// therefore takes the resolved Theme.color object as a plain argument;
// every caller passes `Theme.color` explicitly.

// Theme.color's individual role values are NOT guaranteed to be typed
// `color` objects -- ThemeDefaults.buildColor()'s resolveRef() returns a
// plain "#rrggbb" STRING for a slot ref with no alpha (its opaque() path)
// and only a real Qt.rgba()-built object for an alpha'd one. Assigning
// either to a QML `property color` auto-coerces it (QML's string->color
// parser runs at that assignment), which is why the OLD inline version of
// this code -- `property color cLine: Theme.color.lineStrong` -- worked
// even when the underlying value was a bare string. A plain JS function
// parameter gets NO such coercion: reading `.hsvHue` off a string is
// `undefined`, and Qt.hsva(undefined, NaN, undefined, undefined) silently
// returns an invalid, fully-transparent-black color with no warning
// logged anywhere -- confirmed empirically (this broke NeuralNet's HUD
// eyebrow/hero/row-values/epoch tag, and would equally have broken
// Orbital's, since both flow every Theme.color role through here). toColor()
// forces the coercion explicitly: Qt.tint(v, "#00000000") blends v with a
// fully-transparent tint (a mathematical no-op) purely to route it through
// Qt's real color-construction path, working for a string OR an
// already-real color input alike.
function toColor(v) {
    return Qt.tint(v, "#00000000");
}

// Pure desaturation at constant HSV value -- see themes/ultraviolet-v2's
// measured ramp: #b047ff h277 s0.72 v1.00 -> #c050ff h281 s0.69 ->
// #d35cf7 h287 s0.63 v0.97. Deriving cMark/cValue from lineStrong's own
// hue/value (not hardcoding the design's literal hexes) is what keeps a
// scene coherent on a non-monochrome palette like catppuccin's hue wheel
// -- catppuccin's base16 would otherwise turn a hardcoded hex into an
// unrelated green/yellow smear on top of it.
function rampStep(c, k) {
    return Qt.hsva(c.hsvHue, c.hsvSaturation * k, c.hsvValue, c.a);
}

// `lineStrong`/`dot`/`live`/`critical` are real design-system roles;
// `cMark`/`cValue` are NOT -- they're the 2nd/3rd rungs of the design's
// accent ramp, and there is no role for "a ramp position". k1/k2 default
// to the measured ultraviolet-v2 ramp steps; exposed as parameters only
// in case a future scene wants a different spread.
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
