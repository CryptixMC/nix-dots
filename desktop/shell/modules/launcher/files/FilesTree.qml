import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"

// Real expand/collapse tree, replacing the old v1's single-level "descend/
// ascend through one flat subfolder list" (FilesTab.qml's own header
// comment called this out as a known limitation). A flat array model
// (`nodes`) rendered by one ListView rather than recursive delegates --
// keeps keyboard navigation a single linear index, same reasoning
// GamesTab's flattened nav index used.
//
// No separate "Places" shortcut list above the tree -- an earlier pass had
// one (Desktop/Documents/Downloads/.../Filesystem), but rooting the tree
// at $HOME already makes every one of those reachable as a direct child of
// the root row (which auto-expands on open, see Component.onCompleted),
// so the shortcuts were just duplicating rows the tree already shows.
// "Filesystem" (root "/") specifically isn't reachable from here anymore
// -- the per-segment breadcrumb in FilesTab.qml still reaches it if
// currentDir is ever navigated there some other way (e.g. typed into a
// future path bar), it just isn't a tree row.
//
// Rooted at $HOME, not "/" -- an earlier pass rooted this at the real
// filesystem root, which meant every fresh open auto-expanded through "/"
// down to $HOME and showed every top-level Linux directory (bin, dev,
// proc, sys, usr, var, ...) as siblings above the one row anyone actually
// wants.
//
// Reads/writes FilesState.currentDir directly rather than through a
// threaded property -- it's a singleton precisely so every piece of the
// Files tab can agree on "where are we" without prop-drilling, the same
// convention GamesLibrary/ThemeState/UsageStore already use elsewhere in
// this module.
Item {
    id: root
    width: Theme.spacing.fileTreeWidth
    property real rowsHeight: 0

    // Flat tree model, rooted at $HOME. Collapsing a node caches its
    // removed subtree (see _subtreeCache below) rather than discarding it,
    // so re-expanding a directory you've already looked at is instant --
    // no repeat `find` round trip. The cache is per FilesTab instance
    // (torn down and rebuilt fresh every time the tab's Loader re-
    // activates), so it can never drift far from the real filesystem.
    property var nodes: [
        {
            path: FilesState.homeDir,
            name: FilesState.homeDir.split("/").pop() || FilesState.homeDir,
            depth: 0,
            expanded: false,
            loaded: false,
            hasChildren: true
        }
    ]

    property int currentRowIndex: 0

    function currentRow() {
        return root.nodes[root.currentRowIndex] ?? null;
    }

    // Every arrow-key move through the tree also sets FilesState.currentDir
    // live, so the grid pane previews each highlighted directory as you
    // browse -- the same "highlight IS the selection" behaviour clicking
    // already had, just extended to the keyboard. `_suppressReveal` skips
    // the Connections handler below's own revealPath() for changes that
    // originated *here* -- the row that triggered this is by definition
    // already visible/expanded correctly, so re-walking the tree to
    // re-confirm that on every single arrow-key press was pure wasted
    // work.
    property bool _suppressReveal: false

    function navigateTo(node) {
        if (node && node.path) {
            root._suppressReveal = true;
            FilesState.currentDir = node.path;
        }
    }

    function moveUp() {
        if (root.currentRowIndex <= 0)
            return false;
        root.currentRowIndex--;
        root.navigateTo(root.currentRow());
        return true;
    }

    function moveDown() {
        if (root.currentRowIndex >= root.nodes.length - 1)
            return false;
        root.currentRowIndex++;
        root.navigateTo(root.currentRow());
        return true;
    }

    // Collapse if expanded; otherwise jump to the parent node. Returns
    // false only when there's genuinely nothing left to do (already-
    // collapsed tree root) -- FilesTab.qml treats that as "fall through
    // to a tab switch".
    function moveLeft() {
        const idx = root.currentRowIndex;
        const node = root.nodes[idx];
        if (!node)
            return false;
        if (node.expanded) {
            root.collapse(idx);
            return true;
        }
        if (node.depth === 0)
            return false;
        const parentIdx = root.parentIndexOf(idx);
        if (parentIdx === -1)
            return false;
        root.currentRowIndex = parentIdx;
        root.navigateTo(root.currentRow());
        return true;
    }

    // Expand if collapsed-with-children; descend into the first child if
    // already expanded. Returns false on a leaf directory with no
    // children -- FilesTab.qml moves keyboard focus into the grid in that
    // case, matching the plan's "Left at column 0 -> tree, Right at
    // tree's end -> grid" contract.
    function moveRight() {
        const idx = root.currentRowIndex;
        const node = root.nodes[idx];
        if (!node)
            return false;
        if (!node.hasChildren && node.loaded)
            return false;
        if (!node.expanded) {
            root.toggle(idx);
            return true;
        }
        if (idx + 1 < root.nodes.length && root.nodes[idx + 1].depth > node.depth) {
            root.currentRowIndex = idx + 1;
            root.navigateTo(root.currentRow());
            return true;
        }
        return false;
    }

    function nodeIndexForPath(path) {
        return root.nodes.findIndex(n => n.path === path);
    }

    function parentIndexOf(idx) {
        const depth = root.nodes[idx].depth;
        for (let i = idx - 1; i >= 0; i--) {
            if (root.nodes[i].depth === depth - 1)
                return i;
        }
        return -1;
    }

    function toggle(idx) {
        const node = root.nodes[idx];
        if (!node)
            return;
        if (node.expanded) {
            root.collapse(idx);
        } else if (root._subtreeCache[node.path]) {
            // Previously expanded this session and then collapsed --
            // restore the cached subtree verbatim (including whatever
            // deeper nodes were themselves expanded) instead of re-running
            // `find`. One-shot: consumed on use, refreshed with whatever
            // the subtree looked like at collapse time.
            const list = root.nodes.slice();
            list[idx] = Object.assign({}, node, {
                expanded: true,
                loaded: true
            });
            list.splice(idx + 1, 0, ...root._subtreeCache[node.path]);
            root.nodes = list;
            delete root._subtreeCache[node.path];
        } else {
            root._runExpand(idx);
        }
    }

    // Plain object, mutated in place -- nothing binds to it declaratively
    // (it's only ever read imperatively inside toggle()/collapse()), so it
    // doesn't need the "reassign the whole object" treatment UsageStore.qml
    // documents for properties that actually drive bindings.
    property var _subtreeCache: ({})

    function collapse(idx) {
        const list = root.nodes.slice();
        const node = Object.assign({}, list[idx], {
            expanded: false
        });
        list[idx] = node;
        let end = idx + 1;
        while (end < list.length && list[end].depth > node.depth)
            end++;
        const removed = list.slice(idx + 1, end);
        if (removed.length > 0)
            root._subtreeCache[node.path] = removed;
        list.splice(idx + 1, end - (idx + 1));
        root.nodes = list;
    }

    // Expands go through a serial queue behind one Process rather than one
    // per node -- same batching discipline GamesLibrary.qml already uses
    // for its Steam/Prism scans, and it means a fast double-click can't
    // fire two overlapping `find` calls against the same directory.
    property var _expandQueue: []
    property bool _expandBusy: false

    function _runExpand(idx, onDone) {
        root._expandQueue.push({
            idx: idx,
            onDone: onDone ?? null
        });
        root._pumpExpand();
    }

    function _pumpExpand() {
        if (root._expandBusy || root._expandQueue.length === 0)
            return;
        const job = root._expandQueue[0];
        const node = root.nodes[job.idx];
        if (!node) {
            root._expandQueue.shift();
            root._pumpExpand();
            return;
        }
        root._expandBusy = true;
        expandProc.command = ["find", node.path, "-mindepth", "1", "-maxdepth", "1", "-type", "d", ...root.hiddenArgs(), "-printf", "%f\n"];
        expandProc.running = true;
    }

    // Mirrors FilesState.showHidden -- dotfile directories are excluded
    // at the `find` level itself, same as FilesPane's own listing.
    function hiddenArgs() {
        return FilesState.showHidden ? [] : ["-not", "-name", ".*"];
    }

    function _spliceChildren(idx, names) {
        const list = root.nodes.slice();
        const node = Object.assign({}, list[idx], {
            loaded: true,
            expanded: true,
            hasChildren: names.length > 0
        });
        list[idx] = node;
        const children = names.map(n => ({
            path: `${node.path}/${n}`,
            name: n,
            depth: node.depth + 1,
            expanded: false,
            loaded: false,
            hasChildren: true
        }));
        list.splice(idx + 1, 0, ...children);
        root.nodes = list;
    }

    Process {
        id: expandProc
        stdout: StdioCollector {
            id: expandOut
        }
        onExited: (exitCode, exitStatus) => {
            const job = root._expandQueue.shift();
            if (exitCode === 0 && job) {
                const names = expandOut.text.split("\n").filter(l => l.length > 0).sort((a, b) => a.localeCompare(b));
                root._spliceChildren(job.idx, names);
            }
            root._expandBusy = false;
            if (job && job.onDone)
                job.onDone();
            root._pumpExpand();
        }
    }

    // Lands the keyboard highlight on `fullPath`, expanding whatever
    // ancestors aren't already expanded along the way -- the mechanism
    // behind "the two panes never disagree about where you are" when
    // currentDir changes from anywhere else (the breadcrumb or the grid
    // itself). Paths outside $HOME aren't part of this tree at all -- the
    // pane still shows them fine via FilesState.currentDir directly, there
    // just isn't a row to highlight for them.
    //
    // Every ancestor's path string is known upfront from splitting
    // `fullPath` -- discovering an ancestor's *existence* never depended
    // on first listing its parent, only splicing its children into the
    // right spot in `nodes` did. So the unloaded ancestors are fetched in
    // ONE `find` call with multiple starting points (`%h` in the -printf
    // groups each result back to the root that produced it), then spliced
    // in root-to-leaf in a single cheap JS pass -- not one sequential
    // process spawn per directory level, which is what made opening the
    // Files tab (revealing $HOME) feel slow.
    function revealPath(fullPath) {
        const home = FilesState.homeDir;
        if (fullPath !== home && !fullPath.startsWith(`${home}/`)) {
            root.currentRowIndex = -1;
            return;
        }
        const rest = fullPath.slice(home.length).split("/").filter(s => s.length > 0);
        const ancestors = [home];
        let acc = home;
        for (let i = 0; i < rest.length - 1; i++) {
            acc += `/${rest[i]}`;
            ancestors.push(acc);
        }
        // Restore any collapsed-but-cached ancestors synchronously first
        // -- no reason to wait on a process round trip for a directory
        // this session has already looked at once.
        for (const p of ancestors) {
            const idx = root.nodeIndexForPath(p);
            if (idx !== -1 && !root.nodes[idx].expanded && root._subtreeCache[p])
                root.toggle(idx);
        }
        const toFetch = ancestors.filter(p => {
            const idx = root.nodeIndexForPath(p);
            return idx === -1 || !root.nodes[idx].expanded;
        });
        if (toFetch.length === 0) {
            const idx = root.nodeIndexForPath(fullPath);
            if (idx !== -1)
                root.currentRowIndex = idx;
            return;
        }
        root._batchExpand(toFetch, () => root.revealPath(fullPath));
    }

    // Same job queue shape as _runExpand/_pumpExpand (one Process, serial,
    // never two overlapping `find` calls) but for revealPath's multi-root
    // batch fetch specifically -- kept as a separate Process so an
    // in-flight single-node toggle() and an in-flight reveal can't stomp
    // on each other's command/callback state.
    property var _batchQueue: []
    property bool _batchBusy: false

    function _batchExpand(paths, onDone) {
        root._batchQueue.push({
            paths: paths,
            onDone: onDone ?? null
        });
        root._pumpBatch();
    }

    function _pumpBatch() {
        if (root._batchBusy || root._batchQueue.length === 0)
            return;
        root._batchBusy = true;
        const job = root._batchQueue[0];
        batchProc.command = ["find", ...job.paths, "-mindepth", "1", "-maxdepth", "1", "-type", "d", ...root.hiddenArgs(), "-printf", "%h\t%f\n"];
        batchProc.running = true;
    }

    Process {
        id: batchProc
        stdout: StdioCollector {
            id: batchOut
        }
        onExited: (exitCode, exitStatus) => {
            const job = root._batchQueue.shift();
            if (exitCode === 0 && job) {
                const grouped = {};
                for (const line of batchOut.text.split("\n")) {
                    if (line.length === 0)
                        continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const parent = line.slice(0, tab);
                    const name = line.slice(tab + 1);
                    if (!grouped[parent])
                        grouped[parent] = [];
                    grouped[parent].push(name);
                }
                // job.paths is root-to-leaf ($HOME outward), so each
                // splice below only ever targets a node that either
                // already existed or was just spliced in by the previous
                // iteration -- no ordering dependency on the find results
                // themselves, only on this loop's own order.
                for (const p of job.paths) {
                    const idx = root.nodeIndexForPath(p);
                    if (idx === -1)
                        continue;
                    const names = (grouped[p] ?? []).slice().sort((a, b) => a.localeCompare(b));
                    root._spliceChildren(idx, names);
                }
            }
            root._batchBusy = false;
            if (job && job.onDone)
                job.onDone();
            root._pumpBatch();
        }
    }

    Connections {
        target: FilesState
        function onCurrentDirChanged() {
            if (root._suppressReveal) {
                root._suppressReveal = false;
                return;
            }
            root.revealPath(FilesState.currentDir);
        }
        // Ctrl+H toggling showHidden doesn't retroactively re-filter
        // whatever's already been fetched into `nodes` -- simplest correct
        // fix is to drop back to just the (unexpanded) root and cached
        // subtrees, then let revealPath rebuild the path back down to
        // wherever currentDir currently is with the new filter applied.
        // Loses deeper expansion state on toggle, which is an acceptable
        // trade for never showing a stale mix of filtered/unfiltered rows.
        function onShowHiddenChanged() {
            root.nodes = [
                {
                    path: FilesState.homeDir,
                    name: FilesState.homeDir.split("/").pop() || FilesState.homeDir,
                    depth: 0,
                    expanded: false,
                    loaded: false,
                    hasChildren: true
                }
            ];
            root._subtreeCache = ({});
            root.revealPath(FilesState.currentDir);
        }
    }

    Component.onCompleted: root.revealPath(FilesState.currentDir)

    ListView {
        id: treeList
        anchors.fill: parent
        clip: true
        model: root.nodes
        currentIndex: root.currentRowIndex
        highlightMoveDuration: Theme.motion.hoverColor.duration
        onCurrentIndexChanged: if (currentIndex >= 0)
            positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Rectangle {
            id: rowDelegate
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === root.currentRowIndex
            readonly property real indent: modelData.depth * 12

            // ListView.view guarded -- see GamesTab.qml's identical fix for
            // why a delegate's own view reference can be null mid-teardown.
            width: ListView.view ? ListView.view.width : Theme.spacing.fileTreeWidth
            height: Theme.spacing.fileTreeRowHeight
            radius: Theme.radius.input
            color: isCurrent ? Theme.color.launcherItemSelectedBg : (rowMouse.containsMouse ? ThemeDefaults.alpha(Theme.base16.base02, 0.5) : "transparent")

            Behavior on color {
                ColorAnimation { duration: Theme.motion.hoverColor.duration }
            }

            // Plain anchor-chain layout (chevron -> icon -> label), not a
            // Row positioner -- Row's implicit sizing fought with the
            // explicit left+right anchoring this row needs for correct
            // per-depth indentation, which was the actual cause of rows
            // misrendering/misaligning at deeper tree levels.
            Text {
                id: chevron
                // z above rowMouse below: without this, chevron's own
                // MouseArea never received clicks at all -- rowMouse
                // (declared later, anchors.fill: parent) painted on top of
                // it and swallowed every click including this one, so the
                // "click the chevron to toggle without navigating" affordance
                // silently never worked.
                z: 1
                anchors {
                    left: parent.left
                    leftMargin: 4 + rowDelegate.indent
                    verticalCenter: parent.verticalCenter
                }
                width: 11
                visible: rowDelegate.modelData.hasChildren
                // Plain Unicode triangles (U+25BC/U+25B6), not Nerd Font
                // glyphs -- a prior pass typed literal Nerd Font PUA
                // characters here and they silently landed as empty
                // strings (confirmed by inspecting the file's raw bytes:
                // the ternary's two branches were "" and "", zero content
                // between the quotes), so the chevron never rendered at
                // all despite the click logic underneath being fine.
                text: rowDelegate.modelData.expanded ? "▼" : "▶"
                renderType: Text.NativeRendering
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall - 2

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    onClicked: {
                        root.currentRowIndex = rowDelegate.index;
                        root.toggle(rowDelegate.index);
                    }
                }
            }

            Text {
                id: icon
                anchors {
                    left: chevron.right
                    leftMargin: 2
                    verticalCenter: parent.verticalCenter
                }
                text: "󰉋"
                renderType: Text.NativeRendering
                color: Theme.color.accentPurple
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                anchors {
                    left: icon.right
                    leftMargin: 4
                    right: parent.right
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                text: rowDelegate.modelData.name
                elide: Text.ElideRight
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    root.currentRowIndex = rowDelegate.index;
                    root.navigateTo(rowDelegate.modelData);
                    if (!rowDelegate.modelData.expanded)
                        root.toggle(rowDelegate.index);
                    if (mouse.button === Qt.RightButton)
                        root.contextMenuRequested(rowDelegate.modelData.path, false, mouse.x, mouse.y);
                }
            }
        }
    }

    // FilesTab.qml connects to this to open the shared FilesContextMenu at
    // the right-clicked tree row -- kept as a signal (not a direct call
    // into FilesContextMenu) so FilesTree stays ignorant of the menu's
    // existence, same separation FilesPane uses.
    signal contextMenuRequested(string path, bool isDir, real x, real y)
}
