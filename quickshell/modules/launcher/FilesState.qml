pragma Singleton
import QtQml
import Quickshell

// Shared Files-tab state: current directory, selection, clipboard, view
// prefs. A singleton (not a per-FilesTab property) so it survives the tab
// being torn down and rebuilt by Launcher.qml's Loader on every tab switch
// -- reopening Files should land back where you left it, same reasoning as
// LauncherState.activeTab surviving across the whole popup's lifetime.
QtObject {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")
    property string currentDir: root.homeDir

    // Bumped by FilesOps on every successful mutation -- the thing
    // FilesPane's/FilesTree's own listing Processes watch (alongside
    // currentDir itself) to know when to re-list without needing to care
    // *why* the directory's contents changed.
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

    // Navigating away is the one place selection/clipboard-cut-source
    // implicitly goes stale in a way that would confuse a later paste --
    // clipboard (copy or cut) deliberately survives a directory change
    // (that's the whole point of cut/copy/paste), only the *selection*
    // resets.
    onCurrentDirChanged: root.selection = []
}
