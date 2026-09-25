pragma Singleton
import QtQml

// Left-nav state for the System tab's sectioned layout. A singleton so the
// active section survives the tab's Loader tearing down and rebuilding on
// every tab switch, same reasoning FilesState persists currentDir.
//
// The old runInTerminal() helper that lived here (every privileged/
// long-running action opening a Ghostty window) is gone -- JobRunner.qml
// replaces it everywhere: commands run in-process with streamed output, and
// privileged ones raise a themed prompt via PolkitAgentService instead of a
// terminal asking for a password in plain text.
QtObject {
    id: root

    // Outline/filled pairs, not a single glyph -- same design-system rule
    // as LauncherState.tabs: hollow at rest, solid when the section is
    // active. \u{} escapes rather than literal glyph bytes for the same
    // reason (this codepoint range silently corrupted to empty strings
    // when written as raw UTF-8 earlier in this session).
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
            // No dedicated outline twin exists for this glyph in the Nerd
            // Font set -- md-monitor is already just a hollow bezel
            // outline by design, so it reads correctly in both states.
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
            // Wrench, not the old broom -- broom has no outline twin in
            // the Nerd Font set, and wrench reads just as well for
            // "maintenance" while actually supporting the outline/filled
            // pair every other section gets.
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
            // No outline twin exists for this glyph either (same situation
            // as Display above) -- md-console reads fine unchanged.
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
