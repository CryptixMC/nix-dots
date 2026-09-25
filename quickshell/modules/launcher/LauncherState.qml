pragma Singleton
import QtQml 2.15
import Quickshell

QtObject {
    // The Launcher UI shows a tab bar at the top (Apps/Games/Files/System)
    // to switch between different content sections. This state tracks which tab
    // is currently active, as well as what tabs are available to be selected.
    //
    // Themes is deliberately NOT its own top-level tab -- Liam's own
    // explicit correction, live: "I want the theme tab to be located as a
    // section within system and not its own tab" (real quote from the
    // sessions.db transcript this fix is based on). SystemTab.qml renders
    // it as a section instead; see that file's own header comment.
    property bool visible: false
    property string activeTab: "apps"
    readonly property var tabs: [
        {
            id: "apps",
            // Outline/filled pairs, not a single glyph -- the design
            // system's rule is every icon renders as its hollow outline
            // variant at rest and swaps to the solid-filled twin only
            // while selected. Written as \u{} escapes rather than literal
            // glyph bytes: this exact codepoint range (Nerd Font Material
            // Design Icons, U+F0000+) silently became empty strings when
            // written as raw UTF-8 earlier in this session (see
            // FilesTree.qml's chevron / SystemAbout.qml's hero glyph) --
            // an escape sequence is plain ASCII source text, so it can't
            // hit that byte-corruption path.
            glyphOutline: "\u{F11D9}", // md-view_grid_outline
            glyphFilled: "\u{F0570}", // md-view_grid
            label: "Applications",
            searchable: true
        },
        {
            id: "games",
            glyphOutline: "\u{F0B83}", // md-controller_classic_outline
            glyphFilled: "\u{F0B82}", // md-controller_classic
            label: "Games",
            searchable: true
        },
        {
            id: "files",
            glyphOutline: "\u{F0256}", // md-folder_outline
            glyphFilled: "\u{F024B}", // md-folder
            label: "Files",
            searchable: true
        },
        {
            id: "system",
            glyphOutline: "\u{F08BB}", // md-cog_outline
            glyphFilled: "\u{F0493}", // md-cog
            label: "System",
            // true, not false -- the Keybinds and Install sections both
            // want the shared search box; per-section content decides
            // whether it actually reads searchQuery, same pattern Files/
            // Games already use.
            searchable: true
        }
    ]

    function setTab(id) {
        activeTab = id;
    }

    // Wrap-around neighbor lookup -- shared by both the mouse-click tab
    // pills (unchanged) and the new Tab/arrow-key navigation in
    // Launcher.qml, so keyboard and mouse navigation can never disagree
    // about tab order.
    function tabIndex(id) {
        return tabs.findIndex(t => t.id === id);
    }

    function nextTab() {
        const i = tabIndex(activeTab);
        setTab(tabs[(i + 1) % tabs.length].id);
    }

    function prevTab() {
        const i = tabIndex(activeTab);
        setTab(tabs[(i - 1 + tabs.length) % tabs.length].id);
    }

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}