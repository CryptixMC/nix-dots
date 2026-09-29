pragma Singleton
import QtQml

// Left-nav state for the System tab. A singleton so the active section
// survives the tab's Loader being rebuilt on every tab switch.
QtObject {
    id: root

    // Outline/filled glyph pairs (hollow at rest, solid when active). Use \u{}
    // escapes: raw UTF-8 in this codepoint range corrupts to empty strings.
    readonly property var sections: [
        {
            id: "about",
            glyphOutline: "\u{F02FD}", // md-information_outline
            glyphFilled: "\u{F02FC}", // md-information
            label: "About"
        },
        {
            id: "install",
            glyphOutline: "\u{F0B8F}", // md-download_outline
            glyphFilled: "\u{F01DA}", // md-download
            label: "Install"
        },
        {
            id: "themes",
            glyphOutline: "\u{F0E0C}", // md-palette_outline
            glyphFilled: "\u{F03D8}", // md-palette
            label: "Themes"
        },
        {
            id: "keybinds",
            glyphOutline: "\u{F097B}", // md-keyboard_outline
            glyphFilled: "\u{F030C}", // md-keyboard
            label: "Keybinds"
        },
        {
            id: "monitor",
            glyphOutline: "\u{F0873}", // md-gauge_empty
            glyphFilled: "\u{F04C5}", // md-speedometer
            label: "Monitor"
        },
        {
            id: "display",
            // No outline twin exists; md-monitor already reads as an outline.
            glyphOutline: "\u{F0379}", // md-monitor
            glyphFilled: "\u{F0379}", // md-monitor
            label: "Display"
        },
        {
            id: "services",
            glyphOutline: "\u{F08BB}", // md-cog_outline
            glyphFilled: "\u{F0493}", // md-cog
            label: "Services"
        },
        {
            id: "maintenance",
            // Wrench, since broom has no outline twin.
            glyphOutline: "\u{F0BE0}", // md-wrench_outline
            glyphFilled: "\u{F05B7}", // md-wrench
            label: "Maintenance"
        },
        {
            id: "power",
            glyphOutline: "\u{F0906}", // md-power_standby
            glyphFilled: "\u{F0425}", // md-power
            label: "Power"
        },
        {
            id: "jobs",
            // No outline twin exists; md-console reads fine in both states.
            glyphOutline: "\u{F018D}", // md-console
            glyphFilled: "\u{F018D}", // md-console
            label: "Jobs"
        }
    ]

    property string activeSection: "about"

    function sectionIndex(id) {
        return root.sections.findIndex(s => s.id === id);
    }
}
