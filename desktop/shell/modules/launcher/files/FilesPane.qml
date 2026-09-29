import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"
import ".."

// Right pane: the current directory's contents as a real scrollable grid,
// plus (when a query has no local matches) a flat "Elsewhere" list of
// cross-directory fuzzy matches. Replaces FolderListModel entirely -- its
// caseSensitive-by-default glob filtering was the actual reason "doc"
// could never match "Documents", and it can't expose size/mtime for a
// properties view or feed a real ranked fuzzy filter. One `find` call per
// directory read instead, same idiom GamesLibrary.qml/ThemeEntryLoader.qml
// already use.
Item {
    id: root
    width: parent.width

    property string searchQuery: ""

    signal contextMenuRequested(var entry, real x, real y)
    signal opened(string path, bool isDir)

    readonly property real columnGap: Theme.spacing.fileGridGap
    readonly property int columns: Math.max(1, Math.floor(root.width / (Theme.spacing.fileGridCellSize + root.columnGap)))

    property var rawEntries: []

    Process {
        id: listProc
        stdout: StdioCollector {
            id: listOut
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.rawEntries = [];
                return;
            }
            const items = [];
            for (const line of listOut.text.split("\n")) {
                if (line.length === 0)
                    continue;
                const t1 = line.indexOf("\t");
                const t2 = line.indexOf("\t", t1 + 1);
                const t3 = line.indexOf("\t", t2 + 1);
                if (t1 < 0 || t2 < 0 || t3 < 0)
                    continue;
                const type = line.slice(0, t1);
                const size = parseInt(line.slice(t1 + 1, t2), 10) || 0;
                const mtime = parseFloat(line.slice(t2 + 1, t3)) || 0;
                const name = line.slice(t3 + 1);
                items.push({
                    name: name,
                    path: `${FilesState.currentDir}/${name}`,
                    isDir: type === "d",
                    size: size,
                    mtime: mtime
                });
            }
            root.rawEntries = items;
        }
    }

    function reload() {
        listProc.command = ["find", FilesState.currentDir, "-mindepth", "1", "-maxdepth", "1", "-printf", "%y\t%s\t%T@\t%f\n"];
        listProc.running = true;
    }

    Component.onCompleted: root.reload()

    // currentDir changes are debounced, not reloaded immediately -- the
    // tree's Up/Down browsing sets currentDir live on every keypress (for
    // the preview-as-you-go behaviour), and OS key-repeat fires every
    // ~20-30ms once held. Without this, holding an arrow key spawned a
    // fresh `find` process per keystroke, which is exactly what made
    // browsing feel sluggish/stuttery. refreshToken (a deliberate action
    // like delete/rename/paste) still reloads immediately -- there's no
    // burst to coalesce there, and the user is waiting on that one change
    // specifically.
    Timer {
        id: reloadDebounce
        interval: 90
        onTriggered: root.reload()
    }
    Connections {
        target: FilesState
        function onCurrentDirChanged() {
            reloadDebounce.restart();
        }
        function onRefreshTokenChanged() {
            root.reload();
        }
    }

    readonly property var visibleEntries: root.rawEntries.filter(e => FilesState.showHidden || !e.name.startsWith("."))

    readonly property var sortedEntries: {
        const dir = FilesState.sortDescending ? -1 : 1;
        const list = root.visibleEntries.slice();
        list.sort((a, b) => {
            if (a.isDir !== b.isDir)
                return a.isDir ? -1 : 1;
            if (FilesState.sortBy === "size")
                return (a.size - b.size) * dir;
            if (FilesState.sortBy === "mtime")
                return (a.mtime - b.mtime) * dir;
            return a.name.localeCompare(b.name) * dir;
        });
        return list;
    }

    readonly property bool searching: root.searchQuery.trim().length > 0

    // Directories excluded from both the local recursive search and the
    // cross-directory "Elsewhere" fallback -- measured live against this
    // machine's real $HOME: unpruned, a maxdepth-6 walk returned 219,598
    // lines (18MB of `find` output) for one query, which is why the fuzzy
    // finder felt broken/dead even after the actual bug (see
    // onSearchQueryChanged below) was fixed -- parsing and scoring that
    // much text per keystroke-burst was never going to feel instant. With
    // this list plus maxdepth 3 the same tree drops to ~1,900 lines.
    readonly property var pruneNames: [".git", "node_modules", ".cache", ".local", ".npm", ".cargo", "target", "build", "dist", "__pycache__", ".venv"]

    function pruneArgs() {
        const args = ["("];
        root.pruneNames.forEach((n, i) => {
            if (i > 0)
                args.push("-o");
            args.push("-name", n);
        });
        args.push(")", "-prune", "-o");
        return args;
    }

    // A query searches the whole subtree under the current directory
    // (bounded depth), not just its immediate children -- a folder a few
    // levels down that contains a match stays visible so there's a way to
    // reach it, instead of only ever surfacing the exact matching item
    // itself. `deepMatches` is the raw recursive scan; `relevantNames`
    // reduces that to "which immediate child either matches directly or
    // contains a descendant that does", which is what the grid actually
    // filters by (the grid only ever shows immediate children).
    property var deepMatches: []

    Timer {
        id: deepSearchDebounce
        interval: 150
        onTriggered: root.runDeepSearch()
    }

    function runDeepSearch() {
        if (!root.searching)
            return;
        // Built once, imperatively, right before the process runs -- not
        // a live binding on currentDir, which would re-evaluate mid-flight
        // on every navigation while a query is active. maxdepth 3, not 6
        // -- "a few directories deep" per the ask, and see pruneNames'
        // comment for why 6 was untenable.
        deepSearchProc.command = ["find", FilesState.currentDir, "-mindepth", "1", "-maxdepth", "3", ...root.pruneArgs(), "-printf", "%y\t%p\n"];
        deepSearchProc.running = false;
        deepSearchProc.running = true;
    }

    Process {
        id: deepSearchProc
        stdout: StdioCollector {
            id: deepSearchOut
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.deepMatches = [];
                return;
            }
            const q = root.searchQuery.trim();
            const rows = [];
            for (const line of deepSearchOut.text.split("\n")) {
                if (line.length === 0)
                    continue;
                const tab = line.indexOf("\t");
                if (tab < 0)
                    continue;
                const type = line.slice(0, tab);
                const p = line.slice(tab + 1);
                if (p === FilesState.currentDir)
                    continue;
                const name = p.split("/").pop();
                const score = Fuzzy.score(q, name);
                if (score >= 0)
                    rows.push({
                        path: p,
                        name: name,
                        isDir: type === "d",
                        score: score
                    });
            }
            root.deepMatches = rows;
        }
    }

    // Best score found anywhere under each immediate child -- a folder
    // that doesn't match the query itself but contains a great match
    // ranks close to that match, so it doesn't get buried under
    // unrelated, worse-scoring direct matches.
    readonly property var relevantNames: {
        if (!root.searching)
            return null;
        const prefix = `${FilesState.currentDir}/`;
        const best = {};
        for (const m of root.deepMatches) {
            if (!m.path.startsWith(prefix))
                continue;
            const firstSeg = m.path.slice(prefix.length).split("/")[0];
            if (!(firstSeg in best) || best[firstSeg] < m.score)
                best[firstSeg] = m.score;
        }
        return best;
    }

    readonly property var displayEntries: {
        if (!root.searching)
            return root.sortedEntries;
        const rel = root.relevantNames;
        const matched = root.sortedEntries.filter(e => rel && Object.prototype.hasOwnProperty.call(rel, e.name));
        matched.sort((a, b) => (rel[b.name] ?? -1) - (rel[a.name] ?? -1));
        return matched;
    }

    // Cross-directory search — only meaningful once the recursive search
    // above (the current directory's own subtree) comes up empty for a
    // real query, otherwise it'd just be visual noise under results
    // already answering the question.
    readonly property bool showElsewhere: root.searching && root.displayEntries.length === 0
    property var outsideMatches: []

    Timer {
        id: outsideDebounce
        interval: 180
        onTriggered: root.runOutsideSearch()
    }

    // Checks root.searchQuery directly, NOT root.searching -- this
    // handler runs synchronously off searchQuery's own change signal, and
    // root.searching is a *separate* computed property that also depends
    // on searchQuery. Confirmed live (via a temporary debug trace) that
    // root.searching still read its stale prior value (false) at this
    // exact point even though searchQuery had already become the new
    // text -- QML doesn't guarantee a sibling computed property has
    // re-evaluated by the time an imperative onXChanged handler for the
    // property it depends on runs. That meant this handler always took
    // the "nothing to search" branch below and the debounce timers that
    // kick off the actual `find` calls never started -- the real reason
    // the fuzzy finder looked entirely dead, independent of the
    // maxdepth/pruning fix above.
    onSearchQueryChanged: {
        if (root.searchQuery.trim().length === 0) {
            root.deepMatches = [];
            deepSearchProc.running = false;
            root.outsideMatches = [];
            outsideSearchProc.running = false;
            return;
        }
        deepSearchDebounce.restart();
        outsideDebounce.restart();
    }

    function runOutsideSearch() {
        const q = root.searchQuery.trim();
        if (q.length === 0)
            return;
        // Built once, imperatively, right before the process runs --
        // NOT a live binding on currentDir the way the old version's
        // `command` was, which re-evaluated mid-flight on every
        // navigation while a query was active.
        // -iname prunes at the `find` level itself (unlike the local
        // recursive search, which fetches everything under currentDir and
        // scores in JS), so this was never at risk of the same 200k-line
        // blowup -- still shares pruneNames for consistency and because a
        // giant node_modules/.cache tree slows the *walk* even when most
        // of it never matches -iname.
        outsideSearchProc.command = ["find", FilesState.homeDir, "-mindepth", "1", "-maxdepth", "6", ...root.pruneArgs(), "-iname", `*${q}*`, "-printf", "%y\t%p\n"];
        outsideSearchProc.running = false;
        outsideSearchProc.running = true;
    }

    Process {
        id: outsideSearchProc
        stdout: StdioCollector {
            id: outsideOut
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.outsideMatches = [];
                return;
            }
            const rows = [];
            for (const line of outsideOut.text.split("\n")) {
                if (line.length === 0)
                    continue;
                const tab = line.indexOf("\t");
                if (tab < 0)
                    continue;
                const type = line.slice(0, tab);
                const p = line.slice(tab + 1);
                if (p === FilesState.currentDir || p.startsWith(`${FilesState.currentDir}/`))
                    continue;
                rows.push({
                    path: p,
                    isDir: type === "d",
                    name: p.split("/").pop()
                });
            }
            root.outsideMatches = Fuzzy.filterSort(root.searchQuery, rows, r => r.name).slice(0, 50);
        }
    }

    property int currentIndex: 0
    onDisplayEntriesChanged: {
        if (root.currentIndex >= root.displayEntries.length)
            root.currentIndex = Math.max(0, root.displayEntries.length - 1);
    }

    function currentEntry() {
        return root.displayEntries[root.currentIndex] ?? null;
    }

    // Delete/rename/copy/etc act on the real multi-select when there is
    // one, otherwise fall back to whatever the keyboard/hover cursor is
    // currently sitting on -- so a plain "press Delete" without ever
    // touching Ctrl/Shift-click still does the obvious thing.
    function selectionOrCurrent() {
        if (FilesState.selection.length > 0)
            return FilesState.selection;
        const cur = root.currentEntry();
        return cur ? [cur.path] : [];
    }

    function moveLeft() {
        if (root.displayEntries.length === 0)
            return false;
        const col = root.currentIndex % root.columns;
        if (col === 0)
            return false;
        root.currentIndex--;
        return true;
    }

    function moveRight() {
        if (root.currentIndex >= root.displayEntries.length - 1)
            return false;
        root.currentIndex++;
        return true;
    }

    function moveUp() {
        const target = root.currentIndex - root.columns;
        if (target < 0)
            return false;
        root.currentIndex = target;
        return true;
    }

    function moveDown() {
        const target = root.currentIndex + root.columns;
        if (target >= root.displayEntries.length)
            return false;
        root.currentIndex = target;
        return true;
    }

    function activate() {
        const entry = root.currentEntry();
        if (entry)
            root.opened(entry.path, entry.isDir);
    }

    readonly property real gridHeight: Theme.spacing.launcherTabBodyMaxHeight - Theme.spacing.fileBreadcrumbHeight - (root.showElsewhere ? Theme.spacing.fileOutsideListMaxHeight + Theme.spacing.fileGridGap : 0)

    Column {
        anchors.fill: parent
        spacing: Theme.spacing.fileGridGap

        Item {
            width: parent.width
            height: root.gridHeight

            // Right-click on empty grid space (not a cell) -- New Folder/
            // New File/Paste/Show Hidden/Sort live here. Declared behind
            // the GridView so cell delegates still get first refusal on
            // clicks; only space the grid itself doesn't cover reaches
            // this MouseArea.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: (mouse) => {
                    FilesState.clearSelection();
                    root.contextMenuRequested(null, mouse.x, mouse.y);
                }
            }

            GridView {
                id: grid
                anchors.fill: parent
                clip: true
                cellWidth: Theme.spacing.fileGridCellSize + Theme.spacing.fileGridGap
                cellHeight: Theme.spacing.fileGridCellSize + 20
                model: root.displayEntries
                currentIndex: root.currentIndex
                onCurrentIndexChanged: if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, GridView.Contain)

                delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool current: GridView.isCurrentItem
                readonly property bool selected: FilesState.isSelected(modelData.path)

                // GridView.view guarded -- confirmed live elsewhere in this
                // module (GamesTab.qml) that a delegate's own view
                // reference can be null for an event landing mid-teardown,
                // e.g. switching tabs while the cursor is still over a
                // cell.
                width: (GridView.view ? GridView.view.cellWidth : Theme.spacing.fileGridCellSize + Theme.spacing.fileGridGap) - Theme.spacing.fileGridGap
                height: GridView.view ? GridView.view.cellHeight : Theme.spacing.fileGridCellSize + 20

                Rectangle {
                    id: iconBg
                    width: Theme.spacing.fileGridCellSize
                    height: Theme.spacing.fileGridCellSize - 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: Theme.radius.input
                    color: cell.selected ? Theme.color.launcherItemSelectedBg : (cellMouse.containsMouse ? ThemeDefaults.alpha(Theme.base16.base02, 0.8) : ThemeDefaults.alpha(Theme.base16.base02, 0.5))
                    border.width: cell.current ? 2 : 0
                    border.color: Theme.color.accentPurple

                    Behavior on color {
                        ColorAnimation { duration: Theme.motion.hoverColor.duration }
                    }
                    Behavior on border.width {
                        NumberAnimation { duration: Theme.motion.hoverColor.duration }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.isDir ? "󰉋" : "󰈔"
                        renderType: Text.NativeRendering
                        font.family: Theme.font.family
                        font.pixelSize: 28
                        color: cell.modelData.isDir ? Theme.color.accentPurple : Theme.color.launcherPlaceholderFg
                    }
                }

                Text {
                    anchors {
                        top: iconBg.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 2
                    }
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: cell.modelData.name
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        root.currentIndex = cell.index;
                        if (mouse.button === Qt.RightButton) {
                            if (!FilesState.isSelected(cell.modelData.path))
                                FilesState.selectOnly(cell.modelData.path);
                            root.contextMenuRequested(cell.modelData, mouse.x, mouse.y);
                            return;
                        }
                        if (mouse.modifiers & Qt.ControlModifier) {
                            FilesState.toggleSelect(cell.modelData.path);
                        } else if (mouse.modifiers & Qt.ShiftModifier && FilesState.selection.length > 0) {
                            const anchorPath = FilesState.selection[0];
                            const anchorIdx = root.displayEntries.findIndex(e => e.path === anchorPath);
                            const lo = Math.min(anchorIdx, cell.index);
                            const hi = Math.max(anchorIdx, cell.index);
                            FilesState.setSelection(root.displayEntries.slice(lo, hi + 1).map(e => e.path));
                        } else {
                            FilesState.clearSelection();
                        }
                    }
                    onDoubleClicked: root.opened(cell.modelData.path, cell.modelData.isDir)
                }
            }
            }
        }

        Column {
            width: parent.width
            spacing: 4
            visible: root.showElsewhere

            Text {
                text: "Elsewhere"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                font.bold: true
            }

            ListView {
                width: parent.width
                height: Theme.spacing.fileOutsideListMaxHeight
                clip: true
                model: root.outsideMatches

                delegate: Rectangle {
                    id: outsideRow
                    required property var modelData

                    // ListView.view guarded -- see GamesTab.qml's identical
                    // fix for why a delegate's own view reference can be
                    // null mid-teardown.
                    width: ListView.view ? ListView.view.width : root.width
                    height: Theme.spacing.fileTreeRowHeight
                    radius: Theme.radius.input
                    color: outsideMouse.containsMouse ? ThemeDefaults.alpha(Theme.base16.base02, 0.5) : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: 6
                            right: parent.right
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Text {
                            text: outsideRow.modelData.isDir ? "󰉋" : "󰈔"
                            renderType: Text.NativeRendering
                            color: Theme.color.accentPurple
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        Text {
                            width: parent.width - 20
                            text: outsideRow.modelData.path
                            elide: Text.ElideMiddle
                            color: Theme.color.tooltipFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                    }

                    MouseArea {
                        id: outsideMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Directory hits now navigate instead of always
                        // calling xdg-open on them -- the old version
                        // hardcoded isDir=false for every "Elsewhere" row.
                        onClicked: root.opened(outsideRow.modelData.path, outsideRow.modelData.isDir)
                    }
                }
            }
        }
    }
}
