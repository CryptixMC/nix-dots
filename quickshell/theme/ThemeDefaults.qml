pragma Singleton
import QtQuick

// Baseline non-color token tree every theme starts from — a theme.json is
// entirely optional (proof: themes/ultraviolet/ ships none at all) and only
// needs to declare the keys it wants to override; everything else falls
// back to this baseline via deepMerge(). Also owns the base16-hex-to-
// Theme.color bridge formula, applied identically to every discovered
// theme's base16.yaml — see themes/ultraviolet/base16.yaml's own comments
// for why base0C (not base0E) is this repo's "primary accent" slot
// convention.
QtObject {
    id: root

    readonly property var baseline: ({
        radius: { panel: 8, popup: 6, input: 4, sliderTrack: 3 },
        spacing: {
            borderHairline: 1, borderCard: 2, flush: 0,
            barHeight: 26, barLeftInset: 12, barRightInset: 4, barIconHitSize: 22,
            workspaceDots: 6, activeWindowPad: 14, activeWindowLabelInset: 7, separatorInset: 6,
            tooltipMinWidth: 138, tooltipPadX: 22, tooltipPadY: 18, tooltipLineGap: 2,
            trayGap: 10, trayIconSize: 15,
            volumePopupWidth: 220, volumePopupPadY: 20, volumePopupInsetX: 10, volumePopupGap: 8,
            volumeSliderWidth: 110, volumeSliderHeight: 16, volumePercentLabelWidth: 32,
            toastWidth: 320, toastWindowPadY: 16, toastCardPadY: 16, toastWindowInset: 8, toastCardInset: 8,
            toastGap: 8, toastLineGap: 4, toastListWidth: 300, toastCloseSize: 16,
            launcherWidth: 564, launcherPanelPadY: 20, launcherContentInset: 10, launcherContentGap: 8,
            launcherInputHeight: 36, launcherRowInset: 11, launcherInputTextInset: 9, launcherResultsMaxHeight: 360,
            launcherRowHeight: 34, launcherIndicatorWidth: 2, launcherIconSize: 16, launcherIconLabelGap: 8,
            launcherTabHeight: 30, launcherTabPadX: 10, launcherTabGap: 6, launcherTabIconLabelGap: 6
        },
        font: { family: "JetBrainsMono Nerd Font Mono", sizeBase: 13, sizeSmall: 11, sizeWorkspace: 12, weightBold: true },
        motion: {
            tooltipHoverDelayMs: 400,
            // Fallback for the common case where a client sends
            // expireTimeout -1 ("server picks") — the freedesktop spec's
            // actual default-timeout value, not an edge case.
            toastTimeoutMs: 8000,
            hoverColor: { duration: 180, easing: "OutQuad" },
            criticalBlink: { duration: 500, dimTo: 0.2, restoreTo: 1 }
        },
        effect: { popupElevated: false, popupShadowColor: "transparent", popupShadowOffset: 0 },
        wallpaper: { engine: "static", image: "alyssa.png" }
    })

    // Plain-object recursive merge — override's leaf values win, nested
    // objects merge key-by-key instead of replacing wholesale (so e.g.
    // catppuccin's theme.json can override just motion.hoverColor without
    // having to restate motion.tooltipHoverDelayMs/criticalBlink too).
    function deepMerge(base, override) {
        const result = Object.assign({}, base);
        for (const key in override) {
            const ov = override[key];
            if (ov !== null && typeof ov === "object" && !Array.isArray(ov) && base[key] !== undefined && typeof base[key] === "object") {
                result[key] = root.deepMerge(base[key], ov);
            } else {
                result[key] = ov;
            }
        }
        return result;
    }

    function hexToRgb(hex) {
        const h = hex.replace("#", "");
        return {
            r: parseInt(h.substring(0, 2), 16) / 255,
            g: parseInt(h.substring(2, 4), 16) / 255,
            b: parseInt(h.substring(4, 6), 16) / 255
        };
    }

    function opaque(hex) {
        return "#" + hex.replace("#", "");
    }

    function alpha(hex, a) {
        const c = root.hexToRgb(hex);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Explicit name->enum map rather than bracket-access on the Easing
    // namespace (Easing["OutQuad"]) — that resolution path is untested
    // against this QML engine, this sidesteps the risk entirely.
    readonly property var easingMap: ({
        "Linear": Easing.Linear,
        "OutQuad": Easing.OutQuad,
        "InQuad": Easing.InQuad,
        "OutCubic": Easing.OutCubic,
        "InCubic": Easing.InCubic,
        "OutQuint": Easing.OutQuint,
        "InOutQuad": Easing.InOutQuad
    })

    function resolveEasing(name) {
        return root.easingMap[name] ?? Easing.OutQuad;
    }

    function buildColor(b16) {
        return {
            barBg: root.alpha(b16.base00, 0.92),
            barBorder: root.alpha(b16.base03, 0.6),
            fg: root.opaque(b16.base05),
            workspaceInactive: Qt.rgba(1, 1, 1, 0.07),
            workspaceOccupied: root.alpha(b16.base05, 0.45),
            accentPink: root.opaque(b16.base08),
            accentPurple: root.opaque(b16.base0C),
            purpleHover: root.alpha(b16.base0C, 0.88),
            windowTitleFg: root.alpha(b16.base05, 0.55),
            windowSeparator: Qt.rgba(1, 1, 1, 0.07),
            clockFg: root.alpha(b16.base05, 0.65),
            rightModuleFg: root.alpha(b16.base05, 0.52),
            tooltipBg: root.alpha(b16.base01, 0.98),
            tooltipBorder: root.alpha(b16.base03, 0.95),
            tooltipMuted: root.opaque(b16.base04),
            tooltipFg: root.alpha(b16.base06, 0.8),
            moduleDisabledFg: root.alpha(b16.base05, 0.25),
            launcherBg: root.alpha(b16.base01, 0.97),
            launcherBorder: root.opaque(b16.base03),
            launcherInputBg: root.opaque(b16.base02),
            launcherInputBorder: root.opaque(b16.base0C),
            launcherPlaceholderFg: root.opaque(b16.base04),
            launcherItemSelectedBg: root.alpha(b16.base0C, 0.12)
        };
    }

    // base16 is mandatory (a theme without colors isn't a theme); manifest
    // (theme.json) and componentOverrides are both optional and default to
    // "no overrides at all" — this is what makes a colors-only theme valid.
    //
    // themeDir gets baked directly into the returned wallpaper object (as
    // `dir`) rather than left for a consumer to reconstruct separately from
    // ThemeState.activeThemeName — two independently-bound properties both
    // deriving from the same activeThemeName (e.g. Wallpaper.qml's old
    // `wp`/`wpDir` split) aren't guaranteed to settle in the same binding
    // pass on a live theme switch, and were observed mismatching in
    // practice (wp already showing the new theme's shader filename while
    // wpDir was still the previous theme's directory). Bundling `dir` into
    // the same atomically-reassigned object as `image`/`gif`/`shader`
    // makes that race structurally impossible.
    function build(base16, manifest, componentOverrides, themeDir) {
        const shape = root.deepMerge(root.baseline, manifest ?? ({}));
        shape.motion = Object.assign({}, shape.motion, {
            hoverColor: Object.assign({}, shape.motion.hoverColor, { easing: root.resolveEasing(shape.motion.hoverColor.easing) })
        });
        return {
            // Raw base16 hex values, passed through unmodified — Theme.color
            // is a semantic remapping (accentPurple, tooltipMuted, etc.) that
            // doesn't preserve the full 16-slot palette, but a proper
            // terminal ANSI palette (Theme.qml's Ghostty sync) needs all 16
            // slots, not just the ones Quickshell's own UI happens to use.
            base16: base16,
            color: root.buildColor(base16),
            radius: shape.radius,
            spacing: shape.spacing,
            font: shape.font,
            motion: shape.motion,
            effect: shape.effect,
            wallpaper: Object.assign({}, shape.wallpaper, { dir: `${themeDir}/wallpapers` }),
            componentOverrides: componentOverrides ?? ({})
        };
    }
}
