import QtQml 2.15
import Quickshell 1.0

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
            id: "system",
            glyph: "S",
            label: "System",
            searchable: false
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