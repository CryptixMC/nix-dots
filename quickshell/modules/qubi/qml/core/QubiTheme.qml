pragma Singleton
import QtQuick

// Every visual token Qubi's QML reads, so nothing in this tree imports a
// host shell's theme. Standalone, the defaults below are the whole theme.
// Embedded, the host points `host` at its own theme object (see Qubi.qml's
// `theme` property) and each group resolves, most specific first:
//
//   host.qubi.<group>.<token>   a theme's explicit override for Qubi
//   host.<group>.<token>        the host's own token of the same name
//   defaults.<group>.<token>
//
// so Qubi follows a host theme switch live without the host having to know
// any of Qubi's token names. `host` only needs to look like
// { color, font, radius, spacing, motion, qubi? } -- all optional.
QtObject {
    id: root

    property var host: null

    readonly property var defaults: ({
        color: {
            fg: "#c8c8c8",
            accentPink: "#ff5de0",
            accentPurple: "#b047ff",
            launcherBg: Qt.rgba(8 / 255, 8 / 255, 8 / 255, 0.97),
            launcherBorder: "#212121",
            launcherInputBg: "#0f0f0f",
            launcherInputBorder: "#b047ff",
            launcherPlaceholderFg: "#373737",
            launcherItemSelectedBg: Qt.rgba(176 / 255, 71 / 255, 1, 0.12)
        },
        font: { family: "monospace", sizeBase: 13, sizeSmall: 11 },
        radius: { panel: 8, input: 4 },
        spacing: {
            borderHairline: 1,
            launcherWidthWide: 960, launcherPanelPadY: 20, launcherContentInset: 10, launcherContentGap: 8,
            launcherInputHeight: 36, launcherRowInset: 11, launcherInputTextInset: 9,
            launcherRowHeight: 34, launcherIconLabelGap: 8, launcherTabHeight: 30, launcherTabGap: 6,
            themePillHeight: 34, themePillPadX: 14, themePillGap: 8,
            sessionListWidth: 340, sessionRowHeight: 52, sessionRowPadX: 12, sessionRowGap: 4,
            sessionMetaGap: 4, sessionPreviewPad: 16,
            modelbrowserCardWidth: 200, modelbrowserCardHeight: 120, modelbrowserCardGap: 12,
            modelbrowserGridPad: 4, modelbrowserProgressHeight: 6,
            chatPanelWidth: 440, chatHeaderHeight: 44, chatCloseSize: 24,
            chatBubbleMaxWidth: 340, chatComposerHeight: 44, chatSendSize: 32,
            // chatStatusHeight: the bottom bar carrying the MCP count and
            // the tier/model/token readout. Shorter than a row since it's
            // sizeSmall text only, no touch target.
            chatStatusHeight: 20, chatTierPickerWidth: 220,
            // Composer grows with the text up to this cap (~5 lines),
            // then pins to the newest line rather than growing further.
            chatComposerMaxHeight: 140,
            clipboardPanelWidth: 320, clipboardRowHeight: 34,
            screenctxPanelWidth: 320, screenctxRowHeight: 34,
            voicePanelWidth: 320, voiceRowHeight: 34,
            // Sized generously so the waveform's max possible bar height
            // (see VoiceOverlay.qml's amplitude formula) can never exceed
            // these bounds.
            voiceWaveformWidth: 420, voiceWaveformHeight: 200,
            notesPanelWidth: 320, notesRowHeight: 34,
            comparePanelWidth: 640, compareColumnGap: 12
        },
        motion: {
            // Doubles as ChatOverlay's unmap delay (its closeTimer uses this
            // same value), so this number IS the perceived close latency.
            chatSlide: { duration: 140, easing: Easing.OutCubic }
        }
    })

    function _group(name) {
        const h = root.host;
        return Object.assign({}, root.defaults[name], (h && h[name]) || {}, (h && h.qubi && h.qubi[name]) || {});
    }

    readonly property var color: root._group("color")
    readonly property var font: root._group("font")
    readonly property var radius: root._group("radius")
    readonly property var spacing: root._group("spacing")
    // A theme.json can only spell an easing curve as a string.
    readonly property var _easing: ({
        "Linear": Easing.Linear, "OutQuad": Easing.OutQuad, "InQuad": Easing.InQuad,
        "OutCubic": Easing.OutCubic, "InCubic": Easing.InCubic, "OutQuint": Easing.OutQuint,
        "InOutQuad": Easing.InOutQuad
    })
    readonly property var motion: {
        const m = root._group("motion");
        const slide = Object.assign({}, m.chatSlide);
        if (typeof slide.easing === "string")
            slide.easing = root._easing[slide.easing] ?? Easing.OutCubic;
        return Object.assign({}, m, { chatSlide: slide });
    }
}
