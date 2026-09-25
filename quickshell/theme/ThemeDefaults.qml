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
        // tabPill and workspaceDot are CLAMPED to half the element's height
        // at the point of use, so 999 reads as "fully round" — a pill, a
        // circle. That keeps the shape a token instead of a hardcoded
        // `height / 2`, which is what lets ultraviolet-v2 flatten both to
        // its 3px/1px bevel without a QML edit.
        radius: { panel: 8, popup: 6, input: 4, sliderTrack: 3, tabPill: 999, workspaceDot: 999 },
        spacing: {
            borderHairline: 1, borderCard: 2, flush: 0,
            barHeight: 26, barLeftInset: 12, barRightInset: 4, barIconHitSize: 22,
            // workspaceDots is the GAP between indicators; workspaceDotSize
            // is the indicator itself. workspaceDotBorder at 0 means "solid
            // fill" (the v1 dot); at 1 the indicator becomes a hairline
            // outline that only fills when focused (the v2 square).
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
            // 2:3 (width:height) art frame -- real Steam library cover art
            // ships at 600x900, that exact ratio, so PreserveAspectCrop
            // now shows the whole image instead of cropping a square out
            // of a portrait source (the old 140x140 square ate the top and
            // bottom of every cover). Title/subtitle/badge are overlaid on
            // the art via a gradient scrim rather than a separate row below
            // it, so gameGridRowHeight/gameRecommendedRowHeight only need
            // gameCardImageHeight plus a little breathing room for the
            // hover scale-up, not a whole extra label row's worth.
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
        // sizeDisplay matches tokens.css's --uv-display (64px) -- the one
        // place so far that needs it is LockView.qml's clock, but it earns
        // a real token rather than a one-off literal there since it's a
        // named size in the design system, not something LockView invented.
        font: { family: "JetBrainsMono Nerd Font Mono", sizeBase: 13, sizeSmall: 11, sizeWorkspace: 12, sizeDisplay: 64, weightBold: true },
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

    // Resolves one entry of a theme.json `color` block. JSON can't hold a Qt
    // color, so a value is spelled as one of:
    //
    //   "base0C"       a palette slot, opaque
    //   "base0C@0.88"  a palette slot at an alpha
    //   "#8850ff5c"    a literal, #RRGGBB or #RRGGBBAA (CSS order, so the
    //                  tokens.css values paste in unchanged)
    //   "transparent"
    //
    // Slot refs are resolved against *this theme's* base16, which is what
    // makes a single role table reusable across palettes — ultraviolet-v2
    // and catppuccin can both say "lineStrong": "base0C" and each gets its
    // own violet/mauve. Literals are the escape hatch for the handful of
    // values tokens.css states as raw hex because they're an alpha on a slot
    // the palette doesn't otherwise name.
    function resolveRef(b16, ref) {
        // Already a Qt color / not a ref — pass through untouched so a
        // baseline value can be a Qt.rgba() as well as a string.
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

    // Explicit name->enum map rather than bracket-access on the Easing
    // namespace (Easing["OutQuad"]) — that resolution path is untested
    // against this QML engine, this sidesteps the risk entirely.
    //
    // No Easing.Bezier entry on purpose. ultraviolet-v2's single curve is
    // cubic-bezier(0.2,0,0,1) (Material's standard ease-in-out), which has
    // no stock Qt equivalent — but Bezier needs BOTH easing.type and
    // easing.bezierCurve, and every consumer here binds only
    // `easing.type: Theme.motion.hoverColor.easing`. Adding the case would
    // make any site that forgot the curve silently fall back to linear.
    // "InOutQuad" is the same shape and indistinguishable across the
    // 120-320ms range v2 caps motion at, so v2's theme.json asks for that.
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

    // The design-system role table (see ultraviolet-v2/tokens/tokens.css).
    // Values are refs, resolved against the theme's own base16 by
    // resolveRef() — so this one table works for every palette.
    //
    // These baselines are the system's SCHEMATIC mapping: grey linework,
    // neutral white inversion, accent as a sparse highlight. That's the
    // conservative default for a theme that doesn't ask for anything else
    // (ultraviolet, catppuccin), and it's what ultraviolet-v2's theme.json
    // overrides wholesale to get the Violet mapping.
    //
    // Roles are ADDITIVE — they sit beside the legacy token names below,
    // they don't replace them. That's deliberate: the legacy names are
    // already wired through ~24 QML files, and a theme.json can recolor any
    // of them directly, so most of a restyle needs no QML edit at all. A new
    // role earns its place only where v2 introduces something v1 has no
    // token for (a row hover band, a "this is live" white, a soft divider).
    readonly property var baselineRoles: ({
        ground: "base00",
        groundApp: "base01",
        line: "base03",
        // Slot-relative, not the literal #21212199 the design system states
        // it as — that hex is ultraviolet's own base03 and would have
        // followed catppuccin's palette around as a foreign grey.
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

    // `overrides` is a theme.json `color` block: a flat map of token name ->
    // color ref, which may name a ROLE (lineStrong) or any of the legacy
    // tokens below (launcherBg). Both are just keys in the same returned
    // object, so a theme restyles an existing surface by overriding the
    // token that surface already reads — no indirection, no QML change.
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
            // Own token, not a reuse of workspaceInactive -- that one is
            // tuned for tiny 6px workspace dots, where 7% white is enough
            // to read against a solid dark bar background. Stretched across
            // a wide slider track next to a fully-opaque accentPurple fill,
            // it was nearly invisible (confirmed live: read as "the track
            // has no contrast, everything just looks like shades of
            // purple"). base05 at 30% gives a clearly neutral, clearly
            // visible grey track regardless of how much purple/violet cast
            // a given theme's near-black background carries.
            sliderTrackBg: root.alpha(b16.base05, 0.3),
            // Its own token rather than a reuse of accentPink: base08 is the
            // genuine critical colour elsewhere (battery, temperature), so a
            // theme that wants a different focused workspace — v2 inverts it
            // to base0C — must be able to move this without dragging
            // "something is wrong" along with it.
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
            // The active tab, kept separate from launcherItemSelectedBg (the
            // selected result ROW) so a theme can pull the two apart: the
            // design system makes an active tab a solid inversion with
            // ground-coloured content, while a selected row stays a
            // translucent band. Baselines here are v1's shared values, so
            // nothing moves until a theme asks.
            launcherTabActiveBg: root.alpha(b16.base0C, 0.12),
            launcherTabActiveFg: root.opaque(b16.base0C),
            // Hyprland's own window frame, pushed live by Theme.qml's
            // syncHyprlandBorders(). Named tokens rather than reusing
            // accentPink/accentPurple/tooltipMuted: those are UI roles that
            // happened to look right, and a theme that wants a FLAT border
            // needs to move the two gradient stops together without
            // dragging "something is critical" (base08) along with them.
            // Setting From and To to the same value is how a theme goes
            // flat — the gradient shape stays, which matters because
            // hyprland.nix's matching static setting must keep the exact
            // `{colors, angle}` table shape to survive stylix's mkForce
            // merge (see the comment there).
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
    function build(base16, manifest, componentOverrides, themeDir, availableWallpapers) {
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
            color: root.buildColor(base16, shape.color),
            radius: shape.radius,
            spacing: shape.spacing,
            font: shape.font,
            motion: shape.motion,
            effect: shape.effect,
            // Opaque pass-through of a theme.json's optional `qubi` key: Qubi's
            // own tokens (modules/qubi/qml/core/QubiTheme.qml) live in its
            // tree, not in the baseline above; a theme overrides them here.
            qubi: shape.qubi ?? ({}),
            // `available` is every plain image/gif file under wallpapers/
            // (the Themes tab's picker) — distinct from engine/image/gif/
            // shader below, which is just the one theme.json declares as
            // the default. See Theme.qml's `wallpaper` facade for how a
            // user-picked override (ThemeState.wallpaperOverrides) takes
            // priority over this default when one is set.
            wallpaper: Object.assign({}, shape.wallpaper, { dir: `${themeDir}/wallpapers`, available: availableWallpapers ?? [] }),
            componentOverrides: componentOverrides ?? ({})
        };
    }
}
