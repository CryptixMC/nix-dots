pragma Singleton
import QtQml 2.15
import Quickshell

QtObject {
    // Active tab and the available tabs. Themes is a section inside System,
    // not its own tab.
    property bool visible: false
    property string activeTab: "apps"
    readonly property var tabs: [
        {
            id: "apps",
            // Outline glyph at rest, filled while selected. Written as \u{} escapes
            // because raw UTF-8 for this codepoint range (U+F0000+) got corrupted to empty strings.
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
            // Keybinds and Install sections use the shared search box.
            searchable: true
        }
    ]

    function setTab(id) {
        activeTab = id;
    }

    // Wrap-around neighbor lookup shared by mouse and keyboard tab navigation.
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