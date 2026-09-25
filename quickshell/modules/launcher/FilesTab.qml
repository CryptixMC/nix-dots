import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"

// Real file manager, replacing the old v1 (single-level subfolder list +
// grid, one action: open). Left: FilesTree.qml (Places + a real expand/
// collapse tree). Right: FilesPane.qml (scrollable grid of the current
// directory, fuzzy-filtered, plus cross-directory "Elsewhere" results when
// a query has no local matches). This file composes those two, a
// breadcrumb, and three small overlays (context menu, rename/new-name
// prompt, confirm) around them, and implements the shared nav contract
// (Launcher.qml's moveLeft/moveRight/moveUp/moveDown/activate/handleKey).
Item {
    id: root
    width: parent.width
    // Fixed, not content-derived -- FilesPane's grid and FilesTree's list
    // each scroll *internally* within their own bounded height rather than
    // growing the whole tab, so there's no dynamic implicitHeight to
    // chase (and no risk of GamesTab/FilesTab's old implicitHeight-vs-
    // height binding-loop trap, since nothing here depends on root.height
    // at all).
    readonly property real computedHeight: Theme.spacing.launcherTabBodyMaxHeight
    height: root.computedHeight
    implicitHeight: root.computedHeight

    property string searchQuery: ""
    // Threaded in from Launcher.qml -- restores focus to the shared
    // searchInput once a prompt (the one place in this module that steals
    // active focus) closes.
    property var restoreFocus: null

    // Which side owns Up/Down/Left/Right-within-zone. Right at the grid's
    // true last item, or Left at the tree's true top, is what crosses
    // between zones or falls through to a tab switch -- see moveLeft/
    // moveRight below.
    property string focusZone: "grid"

    readonly property bool hasModalOpen: prompt.visible || contextMenu.visible || confirmOverlay.visible || propertiesOverlay.visible

    property string errorMessage: ""
    Timer {
        id: errorTimer
        interval: 4000
        onTriggered: root.errorMessage = ""
    }
    Connections {
        target: FilesOps
        function onOpFailed(message) {
            root.errorMessage = message;
            errorTimer.restart();
        }
    }

    function openEntry(path, isDir) {
        if (isDir) {
            FilesState.currentDir = path;
            root.focusZone = "grid";
        } else {
            Quickshell.execDetached(["xdg-open", path]);
            LauncherState.hide();
        }
    }

    // ---- nav contract ----

    function moveLeft() {
        if (root.hasModalOpen)
            return true;
        if (root.focusZone === "grid") {
            if (pane.moveLeft())
                return true;
            root.focusZone = "tree";
            return true;
        }
        if (tree.moveLeft())
            return true;
        return false;
    }

    function moveRight() {
        if (root.hasModalOpen)
            return true;
        if (root.focusZone === "tree") {
            if (tree.moveRight())
                return true;
            root.focusZone = "grid";
            return true;
        }
        if (pane.moveRight())
            return true;
        return false;
    }

    function moveUp() {
        if (root.hasModalOpen)
            return true;
        return root.focusZone === "tree" ? tree.moveUp() : pane.moveUp();
    }

    function moveDown() {
        if (root.hasModalOpen)
            return true;
        return root.focusZone === "tree" ? tree.moveDown() : pane.moveDown();
    }

    function activate() {
        if (root.hasModalOpen)
            return;
        if (root.focusZone === "tree")
            root.focusZone = "grid";
        else
            pane.activate();
    }

    // Delete/F2/Ctrl+C/Ctrl+X/Ctrl+V/Escape, forwarded from Launcher.qml's
    // shared searchInput. Escape's own precedence (consume here before the
    // window-level Shortcut closes the whole launcher) is the one thing
    // Files actually needs from this beyond the base contract -- see
    // Launcher.qml's `hasModalOpen`-gated Shortcut for the prompt case,
    // which steals focus outright and so never reaches this function at
    // all.
    function handleKey(key) {
        if (key === "Escape") {
            if (confirmOverlay.visible) {
                confirmOverlay.resolve(false);
                return true;
            }
            if (propertiesOverlay.visible) {
                propertiesOverlay.visible = false;
                return true;
            }
            if (contextMenu.visible) {
                contextMenu.close();
                return true;
            }
            if (FilesState.selection.length > 0) {
                FilesState.clearSelection();
                return true;
            }
            return false;
        }
        if (root.hasModalOpen)
            return true;
        if (key === "Delete") {
            root.requestDelete(pane.selectionOrCurrent());
            return true;
        }
        if (key === "F2") {
            const entry = pane.currentEntry();
            if (entry)
                root.requestRename(entry);
            return true;
        }
        if (key === "Ctrl+C") {
            const paths = pane.selectionOrCurrent();
            if (paths.length > 0)
                FilesState.setClipboard("copy", paths);
            return true;
        }
        if (key === "Ctrl+X") {
            const paths = pane.selectionOrCurrent();
            if (paths.length > 0)
                FilesState.setClipboard("cut", paths);
            return true;
        }
        if (key === "Ctrl+V") {
            root.requestPaste();
            return true;
        }
        if (key === "Ctrl+H") {
            FilesState.showHidden = !FilesState.showHidden;
            return true;
        }
        return false;
    }

    // ---- actions ----

    function requestRename(entry) {
        prompt.open(`Rename "${entry.name}"`, entry.name, (newName) => {
            const newPath = `${FilesState.currentDir}/${newName}`;
            if (newPath !== entry.path)
                FilesOps.rename(entry.path, newPath);
        }, null);
    }

    function requestNewFolder() {
        prompt.open("New Folder", "", (name) => FilesOps.newFolder(FilesState.currentDir, name), null);
    }

    function requestNewFile() {
        prompt.open("New File", "", (name) => FilesOps.newFile(FilesState.currentDir, name), null);
    }

    function requestDelete(paths) {
        if (paths.length === 0)
            return;
        const label = paths.length === 1 ? paths[0].split("/").pop() : `${paths.length} items`;
        confirmOverlay.ask(`Move "${label}" to trash?`, () => {
            FilesOps.trash(paths);
            FilesState.clearSelection();
        });
    }

    function requestPaste() {
        if (!FilesState.clipboard || FilesState.clipboard.paths.length === 0)
            return;
        const destDir = FilesState.currentDir;
        const existingNames = new Set(pane.rawEntries.map(e => e.name));
        const collides = FilesState.clipboard.paths.some(p => existingNames.has(p.split("/").pop()));
        const doPaste = (overwrite) => {
            if (FilesState.clipboard.mode === "copy") {
                FilesOps.copy(FilesState.clipboard.paths, destDir, overwrite);
            } else {
                FilesOps.move(FilesState.clipboard.paths, destDir, overwrite);
                FilesState.clearClipboard();
            }
        };
        if (collides)
            confirmOverlay.ask("One or more items already exist here. Overwrite?", () => doPaste(true));
        else
            doPaste(false);
    }

    function requestProperties(entry) {
        propertiesOverlay.show(entry);
    }

    function openOpenWithSubmenu(entry) {
        contextMenu.stack = contextMenu.stack.concat([
            {
                title: "Open With",
                items: [
                    {
                        label: "Loading…",
                        enabled: false
                    }
                ]
            }
        ]);
        FilesOps.queryOpenWith(entry.path, (ids) => {
            let items = ids.map(id => {
                const de = DesktopEntries.byId(id);
                return de ? {
                    label: de.name,
                    glyph: "󰀻",
                    action: () => {
                        FilesOps.launchEntryWith(de, entry.path);
                        LauncherState.hide();
                    }
                } : null;
            }).filter(x => x !== null);
            if (items.length === 0)
                items = [
                    {
                        label: "No applications found",
                        enabled: false
                    }
                ];
            const stack = contextMenu.stack.slice();
            stack[stack.length - 1] = {
                title: "Open With",
                items: items
            };
            contextMenu.stack = stack;
        });
    }

    readonly property var archiveExtensions: /\.(zip|tar|tar\.gz|tgz|tar\.xz|txz|tar\.zst|tzst)$/i

    function buildCompressSubmenu(paths, baseDir) {
        const items = [
            {
                label: "tar.gz",
                action: () => FilesOps.compress("tar.gz", paths, `${baseDir}/${paths.length === 1 ? paths[0].split("/").pop() : "archive"}.tar.gz`, baseDir)
            },
            {
                label: "tar.zst",
                action: () => FilesOps.compress("tar.zst", paths, `${baseDir}/${paths.length === 1 ? paths[0].split("/").pop() : "archive"}.tar.zst`, baseDir)
            },
            {
                label: "tar.xz",
                action: () => FilesOps.compress("tar.xz", paths, `${baseDir}/${paths.length === 1 ? paths[0].split("/").pop() : "archive"}.tar.xz`, baseDir)
            }
        ];
        if (FilesOps.availableTools.zip)
            items.push({
                label: "zip",
                action: () => FilesOps.compress("zip", paths, `${baseDir}/${paths.length === 1 ? paths[0].split("/").pop() : "archive"}.zip`, baseDir)
            });
        return items;
    }

    function buildFileMenu(entry) {
        const paths = FilesState.isSelected(entry.path) && FilesState.selection.length > 1 ? FilesState.selection : [entry.path];
        const items = [];
        // Plain Unicode glyphs here, not Nerd Font -- a prior pass typed
        // Nerd Font PUA characters for these two and they silently landed
        // as empty strings (same root cause as the tree chevron; see its
        // comment), leaving these menu rows with no icon at all.
        items.push({
            label: "Open",
            glyph: "▸",
            action: () => root.openEntry(entry.path, entry.isDir)
        });
        if (!entry.isDir)
            items.push({
                label: "Open With",
                glyph: "󰀻",
                keepOpen: true,
                action: () => root.openOpenWithSubmenu(entry)
            });
        items.push({
            label: "Open in Terminal",
            glyph: ">",
            action: () => Quickshell.execDetached(["ghostty", "--working-directory=" + (entry.isDir ? entry.path : FilesState.currentDir)])
        });
        items.push({
            separator: true
        });
        items.push({
            label: "Cut",
            glyph: "󰆐",
            action: () => FilesState.setClipboard("cut", paths)
        });
        items.push({
            label: "Copy",
            glyph: "󰆏",
            action: () => FilesState.setClipboard("copy", paths)
        });
        items.push({
            label: "Paste",
            glyph: "󰅌",
            enabled: !!FilesState.clipboard,
            action: () => root.requestPaste()
        });
        items.push({
            separator: true
        });
        if (paths.length === 1)
            items.push({
                label: "Rename",
                glyph: "󰑕",
                action: () => root.requestRename(entry)
            });
        items.push({
            label: "Copy Path",
            glyph: "󰆒",
            action: () => FilesOps.copyTextToClipboard(entry.path)
        });
        items.push({
            label: "Copy Name",
            glyph: "󰆒",
            action: () => FilesOps.copyTextToClipboard(entry.name)
        });
        items.push({
            separator: true
        });
        items.push({
            label: "Compress",
            glyph: "󰗄",
            submenu: root.buildCompressSubmenu(paths, FilesState.currentDir)
        });
        if (!entry.isDir && root.archiveExtensions.test(entry.name))
            items.push({
                label: "Extract Here",
                glyph: "󰛌",
                action: () => FilesOps.extract(entry.path, FilesState.currentDir)
            });
        if (paths.length === 1)
            items.push({
                label: "Properties",
                glyph: "󰋽",
                action: () => root.requestProperties(entry)
            });
        items.push({
            separator: true
        });
        items.push({
            label: paths.length > 1 ? `Delete ${paths.length} items` : "Delete",
            glyph: "󰆴",
            danger: true,
            action: () => root.requestDelete(paths)
        });
        return items;
    }

    function buildEmptyAreaMenu() {
        return [
            {
                label: "New Folder",
                glyph: "󰝰",
                action: () => root.requestNewFolder()
            },
            {
                label: "New File",
                glyph: "󰈔",
                action: () => root.requestNewFile()
            },
            {
                label: "Paste",
                glyph: "󰅌",
                enabled: !!FilesState.clipboard,
                action: () => root.requestPaste()
            },
            {
                separator: true
            },
            {
                label: "Open in Terminal",
                glyph: ">",
                action: () => Quickshell.execDetached(["ghostty", "--working-directory=" + FilesState.currentDir])
            },
            {
                separator: true
            },
            {
                label: FilesState.showHidden ? "Hide Hidden Files" : "Show Hidden Files",
                glyph: "󰈉",
                action: () => FilesState.showHidden = !FilesState.showHidden
            },
            {
                label: "Sort By",
                glyph: "󰒺",
                submenu: [
                    {
                        label: "Name",
                        action: () => FilesState.sortBy = "name"
                    },
                    {
                        label: "Size",
                        action: () => FilesState.sortBy = "size"
                    },
                    {
                        label: "Modified",
                        action: () => FilesState.sortBy = "mtime"
                    },
                    {
                        separator: true
                    },
                    {
                        label: FilesState.sortDescending ? "Descending ✓" : "Ascending ✓",
                        action: () => FilesState.sortDescending = !FilesState.sortDescending
                    }
                ]
            }
        ];
    }

    Column {
        id: mainColumn
        width: parent.width
        spacing: Theme.spacing.fileGridGap

        // Breadcrumb -- per-segment clickable, replacing the old single
        // elided path label. "/" is always the first segment; clicking
        // any segment navigates straight there.
        Row {
            id: breadcrumbRow
            width: parent.width
            height: Theme.spacing.fileBreadcrumbHeight
            spacing: 2
            clip: true

            readonly property var segments: {
                const parts = FilesState.currentDir.split("/").filter(p => p.length > 0);
                const rows = [
                    {
                        label: "/",
                        path: "/"
                    }
                ];
                let acc = "";
                for (const p of parts) {
                    acc += `/${p}`;
                    rows.push({
                        label: p,
                        path: acc
                    });
                }
                return rows;
            }

            Repeater {
                model: breadcrumbRow.segments

                delegate: Row {
                    id: segDelegate
                    required property var modelData
                    required property int index
                    spacing: 2

                    Text {
                        visible: segDelegate.index > 0
                        text: "/"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: segDelegate.modelData.label
                        color: segMouse.containsMouse ? Theme.color.accentPurple : (segDelegate.index === breadcrumbRow.segments.length - 1 ? Theme.color.fg : Theme.color.launcherPlaceholderFg)
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            id: segMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: FilesState.currentDir = segDelegate.modelData.path
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacing.gameSectionGap

            FilesTree {
                id: tree
                height: Theme.spacing.launcherTabBodyMaxHeight - breadcrumbRow.height - mainColumn.spacing

                // (x, y) arrive local to FilesTree itself; tree.x/tree.y
                // (its own position within this Row, both 0 as the first
                // child) plus the breadcrumb's reserved height above
                // converts that into FilesTab-root-relative coordinates,
                // which is what contextMenu (anchors.fill: FilesTab's
                // root) expects.
                onContextMenuRequested: (path, isDir, x, y) => {
                    const entry = {
                        path: path,
                        name: path.split("/").pop(),
                        isDir: isDir
                    };
                    contextMenu.openAt(x + tree.x, y + tree.y + breadcrumbRow.height + mainColumn.spacing, root.buildFileMenu(entry));
                }
            }

            FilesPane {
                id: pane
                // The real bug behind "the grid doesn't show" -- unlike
                // FilesTree just above, this never got an explicit height
                // anywhere (not here, not inside FilesPane.qml's own root
                // Item), so it silently defaulted to 0. Confirmed live: a
                // plain debug Rectangle placed *inside* FilesPane never
                // rendered at any width (tried both the real width
                // expression and a hardcoded 400), while an identical
                // Rectangle placed directly in FilesTab at the same
                // position rendered fine -- so the rest of the layout
                // chain (Row placement, the Loader's clip region) was
                // never the problem, only this missing height.
                height: Theme.spacing.launcherTabBodyMaxHeight - breadcrumbRow.height - mainColumn.spacing
                width: parent.width - tree.width - parent.spacing
                searchQuery: root.searchQuery

                onOpened: (path, isDir) => root.openEntry(path, isDir)
                // pane.x already equals tree.width + Row.spacing (its own
                // position as the second child) -- adding tree.width again
                // here would double-count that offset and open the menu
                // too far right.
                onContextMenuRequested: (entry, x, y) => {
                    const menuItems = entry ? root.buildFileMenu(entry) : root.buildEmptyAreaMenu();
                    contextMenu.openAt(x + pane.x, y + pane.y + breadcrumbRow.height + mainColumn.spacing, menuItems);
                }
            }
        }
    }

    // ---- error banner ----
    Rectangle {
        visible: root.errorMessage.length > 0
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 8
        }
        width: Math.min(parent.width - 40, errorText.implicitWidth + 24)
        height: errorText.implicitHeight + 16
        radius: Theme.radius.popup
        color: ThemeDefaults.alpha(Theme.base16.base00, 0.95)
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.accentPink
        z: 400

        Text {
            id: errorText
            anchors.centerIn: parent
            text: root.errorMessage
            color: Theme.color.accentPink
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            wrapMode: Text.Wrap
            width: Math.min(400, parent.width - 24)
        }
    }

    // ---- overlays ----
    FilesContextMenu {
        id: contextMenu
    }

    FilesPrompt {
        id: prompt
        restoreFocus: root.restoreFocus
    }

    Item {
        id: confirmOverlay
        anchors.fill: parent
        visible: false
        z: 700

        property string message: ""
        property var onYes: null

        function ask(msg, yesFn) {
            confirmOverlay.message = msg;
            confirmOverlay.onYes = yesFn;
            confirmOverlay.visible = true;
        }

        function resolve(yes) {
            const fn = confirmOverlay.onYes;
            confirmOverlay.visible = false;
            confirmOverlay.onYes = null;
            if (yes && fn)
                fn();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: confirmOverlay.resolve(false)
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(320, parent.width - 40)
            height: confirmColumn.implicitHeight + 20
            radius: Theme.radius.popup
            color: Theme.color.launcherBg
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.accentPink

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: confirmColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                spacing: 10

                Text {
                    width: parent.width
                    text: confirmOverlay.message
                    wrapMode: Text.Wrap
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    Rectangle {
                        width: 76
                        height: 28
                        radius: Theme.radius.input
                        color: yesMouse.containsMouse ? Theme.color.accentPink : "transparent"
                        border.width: Theme.spacing.borderHairline
                        border.color: Theme.color.accentPink
                        Text {
                            anchors.centerIn: parent
                            text: "Confirm"
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                        MouseArea {
                            id: yesMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: confirmOverlay.resolve(true)
                        }
                    }
                    Rectangle {
                        width: 76
                        height: 28
                        radius: Theme.radius.input
                        color: noMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                        border.width: Theme.spacing.borderHairline
                        border.color: Theme.color.launcherBorder
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                        MouseArea {
                            id: noMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: confirmOverlay.resolve(false)
                        }
                    }
                }
            }
        }
    }

    Item {
        id: propertiesOverlay
        anchors.fill: parent
        visible: false
        z: 650

        property var entry: null
        property var info: null

        function show(e) {
            propertiesOverlay.entry = e;
            propertiesOverlay.info = null;
            propertiesOverlay.visible = true;
            FilesOps.propertiesFor(e.path, (result) => {
                propertiesOverlay.info = result;
            });
        }

        MouseArea {
            anchors.fill: parent
            onClicked: propertiesOverlay.visible = false
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(360, parent.width - 40)
            height: propsColumn.implicitHeight + 24
            radius: Theme.radius.popup
            color: Theme.color.launcherBg
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.accentPurple

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: propsColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 6

                Text {
                    text: propertiesOverlay.entry ? propertiesOverlay.entry.name : ""
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    font.bold: true
                    elide: Text.ElideMiddle
                    width: parent.width
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: Theme.color.tooltipFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    textFormat: Text.PlainText
                    text: {
                        if (!propertiesOverlay.entry)
                            return "";
                        if (!propertiesOverlay.info)
                            return "Loading…";
                        const d = propertiesOverlay.info;
                        const when = new Date(d.mtimeEpoch * 1000).toLocaleString();
                        return `Location: ${propertiesOverlay.entry.path}\nType: ${d.mime || d.kind}\nSize: ${d.diskUsage} (${d.size} bytes)\nOwner: ${d.owner}\nPermissions: ${d.perms}\nModified: ${when}`;
                    }
                }

                Rectangle {
                    width: 76
                    height: 28
                    anchors.right: parent.right
                    radius: Theme.radius.input
                    color: closeMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherBorder
                    Text {
                        anchors.centerIn: parent
                        text: "Close"
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: propertiesOverlay.visible = false
                    }
                }
            }
        }
    }
}
