pragma Singleton
import QtQml
import Quickshell

// Shared Files-tab state. A singleton so it survives the tab's Loader being
// torn down on every tab switch.
QtObject {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")
    property string currentDir: root.homeDir

    // Bumped by FilesOps after each successful mutation so listings re-read.
    property int refreshToken: 0

    property var selection: []
    // {mode: "copy"|"cut", paths: [...]}
    property var clipboard: null

    property bool showHidden: false
    // "name" | "size" | "mtime"
    property string sortBy: "name"
    property bool sortDescending: false

    function isSelected(path) {
        return root.selection.indexOf(path) >= 0;
    }

    function selectOnly(path) {
        root.selection = path ? [path] : [];
    }

    function toggleSelect(path) {
        const i = root.selection.indexOf(path);
        root.selection = i >= 0 ? root.selection.filter(p => p !== path) : root.selection.concat([path]);
    }

    function setSelection(paths) {
        root.selection = paths;
    }

    function clearSelection() {
        root.selection = [];
    }

    function setClipboard(mode, paths) {
        root.clipboard = {
            mode: mode,
            paths: paths
        };
    }

    function clearClipboard() {
        root.clipboard = null;
    }

    // Selection resets on navigation; the clipboard deliberately survives.
    onCurrentDirChanged: root.selection = []
}
