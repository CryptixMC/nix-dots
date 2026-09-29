pragma Singleton
import QtQuick

// Baseline non-color token tree every theme deep-merges over (theme.json is
// optional), plus the base16-to-Theme.color formula. base0C is the primary accent
// slot (see desktop/themes/ultraviolet/base16.yaml).
QtObject {
    id: root

    readonly property var baseline: ({
        // tabPill and workspaceDot are clamped to half the element height at use,
        // so 999 means fully round while themes can still flatten them.
        radius: { panel: 8, popup: 6, input: 4, sliderTrack: 3, tabPill: 999, workspaceDot: 999 },
        spacing: {
            borderHairline: 1, borderCard: 2, flush: 0,
            barHeight: 26, barLeftInset: 12, barRightInset: 4, barIconHitSize: 22,
            // workspaceDots is the gap; workspaceDotBorder 0 = solid fill, 1 = hairline
            // outline filled only when focused.
            workspaceDots: 6, workspaceDotSize: 6, workspaceDotBorder: 0,
            activeWindowPad: 14, activeWindowLabelInset: 7, separatorInset: 6,
            tooltipMinWidth: 138, tooltipPadX: 22, tooltipPadY: 18, tooltipLineGap: 2,
            trayGap: 10, trayIconSize: 15, trayMenuWidth: 200,
            volumePopupWidth: 220, volumePopupPadY: 20, volumePopupInsetX: 10, volumePopupGap: 8,
            volumeSliderWidth: 110, volumeSliderHeight: 16, volumePercentLabelWidth: 32,
            toastWidth: 320, toastWindowPadY: 16, toastCardPadY: 16, toastWindowInset: 8, toastCardInset: 8,
            toastGap: 8, toastLineGap: 4, toastListWidth: 300, toastCloseSize: 16,
            launcherWidth: 564, launcherWidthWide: 960, launcherPanelPadY: 20, launcherContentInset: 10, launcherContentGap: 8,
            launcherInputHeight: 36, launcherRowInset: 11, launcherInputTextInset: 9, launcherResultsMaxHeight: 360,
            launcherRowHeight: 34, launcherIndicatorWidth: 2, launcherIconSize: 16, launcherIconLabelGap: 8,
            launcherTabHeight: 30, launcherTabPadX: 10, launcherTabGap: 6, launcherTabIconLabelGap: 6,
            launcherTabBodyMaxHeight: 520,
            themePillHeight: 34, themePillPadX: 14, themePillGap: 8, themeRowGap: 14,
            themeWallpaperThumbWidth: 128, themeWallpaperThumbHeight: 80, themeWallpaperGap: 10,
            // 2:3 frame matches Steam cover art (600x900). Labels overlay the art, so
            // row heights only add room for the hover scale-up.
            gameCardWidth: 130, gameCardImageHeight: 195, gameCardGap: 14, gameSectionGap: 20,
            gameRecommendedRowHeight: 206, gameGridRowHeight: 212, gameSectionHeaderGap: 8,
            fileTreeWidth: 220, fileTreeRowHeight: 22, fileGridCellSize: 92, fileGridGap: 12,
            fileBreadcrumbHeight: 24, fileOutsideListMaxHeight: 120,
            authPromptWidth: 340, authPromptPadX: 24, authPromptPadY: 22, authPromptGap: 12,
            authPromptIconSize: 32, authPromptInputHeight: 34,
            jobCardPadX: 10, jobCardPadY: 8, jobCardGap: 10, jobHeaderGap: 8,
            jobOutputMaxHeight: 220, jobOutputPad: 8,
            historyGraphHeight: 64, historyGraphLineWidth: 1.5, historyGraphFillAlpha: 0.15,
            sparklineWidth: 40, sparklineHeight: 14, sparklineLineWidth: 1,
            qsPanelWidth: 300, qsPanelPadX: 16, qsPanelPadY: 16, qsSectionGap: 14,
            qsTileSize: 68, qsTileGap: 8, qsTileIconSize: 18, qsTileRadius: 10,
            qsSliderRowGap: 8, qsSliderHeight: 14, qsSliderIconWidth: 20,
            qsMediaArtSize: 40, qsMediaGap: 10, qsFooterGap: 12,
            calendarWidth: 240, calendarPadX: 14, calendarPadY: 14, calendarCellSize: 28,
            calendarHeaderGap: 8, calendarRowGap: 2,
            mediaWidgetMaxLabelWidth: 140,
            notifCenterWidth: 320, notifCenterMaxHeight: 400, notifCenterPad: 12,
            notifCenterCardPad: 10, notifCenterGap: 8,
            osdWidth: 220, osdHeight: 56, osdPadX: 16, osdIconSize: 20
        },
        // sizeDisplay matches tokens.css's --uv-display (64px).
        font: { family: "JetBrainsMono Nerd Font Mono", sizeBase: 13, sizeSmall: 11, sizeWorkspace: 12, sizeDisplay: 64, weightBold: true },
        motion: {
            tooltipHoverDelayMs: 400,
            // Used when a client sends expireTimeout -1 ("server picks").
            toastTimeoutMs: 8000,
            hoverColor: { duration: 180, easing: "OutQuad" },
            criticalBlink: { duration: 500, dimTo: 0.2, restoreTo: 1 }
        },
        effect: { popupElevated: false, popupShadowColor: "transparent", popupShadowOffset: 0 },
        wallpaper: { engine: "static", image: "alyssa.png" }
    })

    // Recursive merge: leaf values override, nested objects merge key-by-key.
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

    // Resolves one theme.json `color` value (JSON can't hold a Qt color):
    //   "base0C"       a palette slot, opaque
    //   "base0C@0.88"  a palette slot at an alpha
    //   "#8850ff5c"    a literal, #RRGGBB or #RRGGBBAA (CSS order)
    //   "transparent"
    // Slot refs resolve against this theme's base16, so one role table fits every palette.
    function resolveRef(b16, ref) {
        // Non-string values (e.g. Qt.rgba() baselines) pass through.
        if (typeof ref !== "string")
            return ref;
        if (ref === "transparent")
            return ref;
        if (ref.charAt(0) === "#") {
            const h = ref.substring(1);
            // hexToRgb reads the first 6 digits, so an 8-digit literal only
            // needs its trailing alpha pair split off here.
            return h.length === 8 ? root.alpha(h, parseInt(h.substring(6, 8), 16) / 255) : ref;
        }
        const at = ref.indexOf("@");
        const slot = at === -1 ? ref : ref.substring(0, at);
        const hex = b16[slot];
        if (hex === undefined) {
            console.warn(`ThemeDefaults: unknown color ref "${ref}" (no such base16 slot "${slot}")`);
            return "transparent";
        }
        return at === -1 ? root.opaque(hex) : root.alpha(hex, parseFloat(ref.substring(at + 1)));
    }

    // Explicit map rather than Easing[name], whose resolution is untested here.
    // No Bezier on purpose: consumers bind only easing.type, so a Bezier without
    // bezierCurve would silently become linear.
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

    // Design-system role table (see ultraviolet-v2/tokens/tokens.css) as refs
    // resolved per theme; baselines are the conservative schematic mapping. Roles
    // sit beside the legacy tokens below, and themes can override either.
    readonly property var baselineRoles: ({
        ground: "base00",
        groundApp: "base01",
        line: "base03",
        // Slot-relative rather than a literal hex, so it follows each palette.
        lineSoft: "base03@0.6",
        lineStrong: "base06",
        textBody: "base05",
        textLabel: "base06",
        textStrong: "base07",
        textDim: "base04",
        textDisabled: "base04",
        invertBg: "base07",
        invertBgHover: "base06",
        invertBgActive: "base05",
        bandHover: "base02",
        bandSelected: "base03",
        live: "base0C",
        focus: "base0C",
        critical: "base08",
        dot: "base0F"
    })

    // `overrides` is a theme.json `color` block mapping any role or legacy token
    // name to a color ref.
    function buildColor(b16, overrides) {
        const roles = {};
        for (const name in root.baselineRoles)
            roles[name] = root.resolveRef(b16, root.baselineRoles[name]);

        const legacy = {
            barBg: root.alpha(b16.base00, 0.92),
            barBorder: root.alpha(b16.base03, 0.6),
            fg: root.opaque(b16.base05),
            workspaceInactive: Qt.rgba(1, 1, 1, 0.07),
            workspaceOccupied: root.alpha(b16.base05, 0.45),
            // Own token: workspaceInactive's 7% white is invisible as a wide track.
            sliderTrackBg: root.alpha(b16.base05, 0.3),
            // Separate from accentPink (base08 means critical elsewhere) so a theme
            // can move the focused workspace colour independently.
            workspaceFocused: root.opaque(b16.base08),
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
            launcherItemSelectedBg: root.alpha(b16.base0C, 0.12),
            // Separate from launcherItemSelectedBg (selected row) so themes can
            // style the active tab differently.
            launcherTabActiveBg: root.alpha(b16.base0C, 0.12),
            launcherTabActiveFg: root.opaque(b16.base0C),
            // Pushed by Theme.qml's syncHyprlandBorders(). Dedicated tokens so a flat
            // border (From == To) doesn't drag UI roles along.
            hyprBorderActiveFrom: root.opaque(b16.base08),
            hyprBorderActiveTo: root.opaque(b16.base0C),
            hyprBorderInactive: root.alpha(b16.base04, 0.667)
        };

        const out = Object.assign({}, roles, legacy);
        for (const name in overrides ?? ({})) {
            if (out[name] === undefined)
                console.warn(`ThemeDefaults: theme.json color."${name}" isn't a known role or token — ignoring`);
            else
                out[name] = root.resolveRef(b16, overrides[name]);
        }
        return out;
    }

    // base16 is mandatory; manifest (theme.json) and componentOverrides are optional.
    // themeDir is baked into the wallpaper object as `dir` so file and directory
    // change atomically on a theme switch; separate bindings can race.
    function build(base16, manifest, componentOverrides, themeDir, availableWallpapers) {
        const shape = root.deepMerge(root.baseline, manifest ?? ({}));
        shape.motion = Object.assign({}, shape.motion, {
            hoverColor: Object.assign({}, shape.motion.hoverColor, { easing: root.resolveEasing(shape.motion.hoverColor.easing) })
        });
        return {
            // Raw palette; Theme.color drops slots the terminal sync needs.
            base16: base16,
            color: root.buildColor(base16, shape.color),
            radius: shape.radius,
            spacing: shape.spacing,
            font: shape.font,
            motion: shape.motion,
            effect: shape.effect,
            // Pass-through of theme.json's optional `qubi` key (tokens live in
            // modules/qubi/qml/core/QubiTheme.qml).
            qubi: shape.qubi ?? ({}),
            // `available` lists pickable image/gif files; engine/image/gif/shader is
            // the theme.json default. Theme.qml applies user overrides.
            wallpaper: Object.assign({}, shape.wallpaper, { dir: `${themeDir}/wallpapers`, available: availableWallpapers ?? [] }),
            componentOverrides: componentOverrides ?? ({})
        };
    }
}
