import QtQml 2.15
import Quickshell 1.0

QtObject {
    // The Launcher UI shows a tab bar at the top (Apps/Games/Files/Themes)
    // to switch between different content sections. This state tracks which tab
    // is currently active, as well as what tabs are available to be selected.
    property string activeTab: "apps"
    readonly property var tabs: [
        {
            id: "apps",
            glyph: "A",
            label: "Applications",
            searchable: true
        },
        {
            id: "games",
            glyph: "G",
            label: "Games",
            searchable: true
        },
        {
            id: "files",
            glyph: "F",
            label: "Files",
            searchable: true
        },
        {
            id: "themes",
            glyph: "T",
            label: "Themes",
            searchable: false
        },
        {
            id: "system",
            glyph: "S",
            label: "System",
            searchable: false
        }
    ]

    function setTab(id) {
        activeTab = id;
    }

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}