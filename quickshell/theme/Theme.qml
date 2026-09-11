pragma Singleton
import QtQuick

// Theme registry: a static catalog of complete token trees (color, radius,
// spacing, font, motion, effect), one active at a time (picked by
// ThemeState.activeThemeName). Replaces the old flat, mostly-color
// Colors.qml — a theme here can restyle the UI's actual shape, not just
// recolor it. `float` reproduces Colors.qml's exact prior appearance
// (verified 1:1 against its literals plus every hardcoded value audited
// across modules/bar, modules/notifications, modules/launcher); `slab` is a
// deliberately different second theme proving radius/spacing/motion/effect
// are real per-theme levers, not just color.
QtObject {
    id: root

    readonly property var themes: ({
        float: {
            color: {
                barBg: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.92),
                barBorder: Qt.rgba(33 / 255, 33 / 255, 33 / 255, 0.6),
                fg: "#c8c8c8",
                workspaceInactive: Qt.rgba(1, 1, 1, 0.07),
                workspaceOccupied: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.45),
                accentPink: "#ff5de0",
                accentPurple: "#b047ff",
                purpleHover: Qt.rgba(176 / 255, 71 / 255, 255 / 255, 0.88),
                windowTitleFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.55),
                windowSeparator: Qt.rgba(1, 1, 1, 0.07),
                clockFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.65),
                rightModuleFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.52),
                tooltipBg: Qt.rgba(6 / 255, 6 / 255, 9 / 255, 0.98),
                tooltipBorder: Qt.rgba(33 / 255, 33 / 255, 33 / 255, 0.95),
                tooltipMuted: "#505050",
                tooltipFg: Qt.rgba(245 / 255, 245 / 255, 245 / 255, 0.8),
                moduleDisabledFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.25),
                launcherBg: Qt.rgba(10 / 255, 10 / 255, 13 / 255, 0.97),
                launcherBorder: "#1c1c1c",
                launcherInputBg: "#0c0c0f",
                launcherInputBorder: "#9150ff",
                launcherPlaceholderFg: "#2e2e2e",
                launcherItemSelectedBg: Qt.rgba(176 / 255, 71 / 255, 255 / 255, 0.12)
            },
            radius: {
                panel: 8,
                popup: 6,
                input: 4,
                sliderTrack: 3
            },
            spacing: {
                borderHairline: 1,
                borderCard: 2,
                flush: 0,
                barHeight: 26,
                barLeftInset: 12,
                barRightInset: 4,
                barIconHitSize: 22,
                workspaceDots: 6,
                activeWindowPad: 14,
                activeWindowLabelInset: 7,
                separatorInset: 6,
                tooltipMinWidth: 138,
                tooltipPadX: 22,
                tooltipPadY: 18,
                tooltipLineGap: 2,
                trayGap: 10,
                trayIconSize: 15,
                volumePopupWidth: 220,
                volumePopupPadY: 20,
                volumePopupInsetX: 10,
                volumePopupGap: 8,
                volumeSliderWidth: 110,
                volumeSliderHeight: 16,
                volumePercentLabelWidth: 32,
                toastWidth: 320,
                toastWindowPadY: 16,
                toastCardPadY: 16,
                toastWindowInset: 8,
                toastCardInset: 8,
                toastGap: 8,
                toastLineGap: 4,
                toastListWidth: 300,
                launcherWidth: 564,
                launcherPanelPadY: 20,
                launcherContentInset: 10,
                launcherContentGap: 8,
                launcherInputHeight: 36,
                launcherRowInset: 11,
                launcherInputTextInset: 9,
                launcherResultsMaxHeight: 360,
                launcherRowHeight: 34,
                launcherIndicatorWidth: 2,
                launcherIconSize: 16,
                launcherIconLabelGap: 8
            },
            font: {
                family: "JetBrainsMono Nerd Font Mono",
                sizeBase: 13,
                sizeSmall: 11,
                sizeWorkspace: 12,
                weightBold: true
            },
            motion: {
                tooltipHoverDelayMs: 400,
                hoverColor: {
                    duration: 180,
                    easing: Easing.OutQuad
                },
                criticalBlink: {
                    duration: 500,
                    dimTo: 0.2,
                    restoreTo: 1
                }
            },
            effect: {
                popupElevated: false,
                popupShadowColor: "transparent",
                popupShadowOffset: 0
            }
        },
        slab: {
            color: {
                barBg: Qt.rgba(5 / 255, 5 / 255, 5 / 255, 0.92),
                barBorder: Qt.rgba(33 / 255, 33 / 255, 33 / 255, 0.6),
                fg: "#c8c8c8",
                workspaceInactive: Qt.rgba(1, 1, 1, 0.07),
                workspaceOccupied: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.45),
                accentPink: "#4de0ff",
                accentPurple: "#3a7bff",
                purpleHover: Qt.rgba(58 / 255, 123 / 255, 255 / 255, 0.88),
                windowTitleFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.55),
                windowSeparator: Qt.rgba(1, 1, 1, 0.07),
                clockFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.65),
                rightModuleFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.52),
                tooltipBg: Qt.rgba(6 / 255, 6 / 255, 9 / 255, 0.98),
                tooltipBorder: Qt.rgba(33 / 255, 33 / 255, 33 / 255, 0.95),
                tooltipMuted: "#505050",
                tooltipFg: Qt.rgba(245 / 255, 245 / 255, 245 / 255, 0.8),
                moduleDisabledFg: Qt.rgba(200 / 255, 200 / 255, 200 / 255, 0.25),
                launcherBg: Qt.rgba(10 / 255, 10 / 255, 13 / 255, 0.97),
                launcherBorder: "#1c1c1c",
                launcherInputBg: "#0c0c0f",
                launcherInputBorder: "#3a7bff",
                launcherPlaceholderFg: "#2e2e2e",
                launcherItemSelectedBg: Qt.rgba(58 / 255, 123 / 255, 255 / 255, 0.12)
            },
            radius: {
                panel: 2,
                popup: 0,
                input: 0,
                sliderTrack: 1
            },
            spacing: {
                borderHairline: 1,
                borderCard: 2,
                flush: 1,
                barHeight: 24,
                barLeftInset: 12,
                barRightInset: 4,
                barIconHitSize: 22,
                workspaceDots: 6,
                activeWindowPad: 14,
                activeWindowLabelInset: 7,
                separatorInset: 6,
                tooltipMinWidth: 138,
                tooltipPadX: 16,
                tooltipPadY: 12,
                tooltipLineGap: 2,
                trayGap: 10,
                trayIconSize: 15,
                volumePopupWidth: 220,
                volumePopupPadY: 20,
                volumePopupInsetX: 10,
                volumePopupGap: 8,
                volumeSliderWidth: 110,
                volumeSliderHeight: 16,
                volumePercentLabelWidth: 32,
                toastWidth: 320,
                toastWindowPadY: 16,
                toastCardPadY: 16,
                toastWindowInset: 8,
                toastCardInset: 6,
                toastGap: 8,
                toastLineGap: 4,
                toastListWidth: 300,
                launcherWidth: 564,
                launcherPanelPadY: 20,
                launcherContentInset: 8,
                launcherContentGap: 8,
                launcherInputHeight: 36,
                launcherRowInset: 11,
                launcherInputTextInset: 9,
                launcherResultsMaxHeight: 360,
                launcherRowHeight: 34,
                launcherIndicatorWidth: 2,
                launcherIconSize: 16,
                launcherIconLabelGap: 8
            },
            font: {
                family: "JetBrainsMono Nerd Font Mono",
                sizeBase: 13,
                sizeSmall: 11,
                sizeWorkspace: 12,
                weightBold: true
            },
            motion: {
                tooltipHoverDelayMs: 400,
                hoverColor: {
                    duration: 90,
                    easing: Easing.Linear
                },
                criticalBlink: {
                    duration: 260,
                    dimTo: 0.15,
                    restoreTo: 1
                }
            },
            effect: {
                popupElevated: true,
                popupShadowColor: Qt.rgba(0, 0, 0, 0.4),
                popupShadowOffset: 3
            }
        }
    })

    readonly property var current: root.themes[ThemeState.activeThemeName] ?? root.themes.float

    readonly property var color: root.current.color
    readonly property var radius: root.current.radius
    readonly property var spacing: root.current.spacing
    readonly property var font: root.current.font
    readonly property var motion: root.current.motion
    readonly property var effect: root.current.effect
}
