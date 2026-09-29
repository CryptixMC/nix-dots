import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../../theme"

// Walker "float" mode replica: centered search box + app list, shown/hidden
// via IPC from a Hyprland keybind (`quickshell ipc -p ~/nix-dots/quickshell
// call launcher toggle` — -p goes before the subcommand, after it errors
// out) rather than process kill/relaunch — this runs inside the same
// already-running Quickshell instance as the bar, so toggling needs to be
// instant. Colors/dimensions mirror the old Walker "float" theme's
// styling (see Colors.qml's launcher* tokens) — rail/grid modes aren't
// replicated, out of scope for this pass.
// Ranking (frecency) and keyword/genericName/comment matching live in
// UsageStore.qml and the filteredEntries property below — a later pass on
// top of the original v1.
//
// Template is modules/notifications/Toast.qml (this repo's only other
// popup/overlay PanelWindow) with two deltas: full-screen anchors (to center
// the box and host a click-outside-to-close backdrop) instead of top-right,
// and focusable: true since this is the first window here that needs
// keyboard input.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: LauncherState.visible
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    // Overlay so the launcher draws above a fullscreen window, same
    // reasoning as Toast.qml's identical override.
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    // Window-wide catch-all so Escape always closes the launcher regardless
    // of which tab is active — searchInput's own identical handler (below)
    // covers the common case, but the Themes tab hides that TextInput
    // entirely (nothing to search there), and an invisible item's focus/
    // key-handling behavior isn't reliable enough to lean on alone. Shortcut
    // (not Keys — PanelWindow isn't an Item, so the Keys attached property
    // can't attach to it directly) works regardless of which child has
    // active focus.
    //
    // `enabled` is gated on the active tab's own `hasModalOpen` (Files'
    // rename prompt is the first thing in this module to steal active
    // focus onto a second TextInput) — while that field has focus,
    // searchInput's own Keys.onEscapePressed below never fires at all
    // (different focused item), so this window-level Shortcut is the ONLY
    // path that would otherwise close the whole launcher out from under
    // an open rename prompt instead of just cancelling it. Disabling the
    // Shortcut outright sidesteps any question of event-ordering between
    // it and the prompt's own Escape handler, rather than trying to race
    // it in onActivated.
    Shortcut {
        sequence: "Escape"
        enabled: !(root.activeTabItem && root.activeTabItem.hasModalOpen === true)
        onActivated: {
            if (!root.callNav("handleKey", false, "Escape"))
                LauncherState.hide();
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            LauncherState.toggle();
        }
        function setTab(tab: string): void {
            LauncherState.setTab(tab);
        }
    }

    // Ranked by: name match before keyword/genericName/comment-only match
    // (so typing "minecraft" surfaces both an app actually named that *and*
    // Prism Launcher, whose Keywords= includes "minecraft", but the literal
    // name match wins the top slot) — then by UsageStore's frecency score
    // within each tier, then alphabetically as a final tiebreak. With an
    // empty query, everything is a "name tier" match trivially, so this
    // collapses to a pure frecency-then-alphabetical "recently/frequently
    // used" list up front, same as Walker.
    readonly property var filteredEntries: {
        const q = searchInput.text.trim().toLowerCase();
        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay);

        const ranked = [];
        for (const e of all) {
            const nameMatch = q.length === 0 || e.name.toLowerCase().includes(q);
            const otherMatch = !nameMatch && ((e.genericName && e.genericName.toLowerCase().includes(q)) || (e.comment && e.comment.toLowerCase().includes(q)) || (e.keywords ?? []).some(k => k.toLowerCase().includes(q)));
            if (nameMatch || otherMatch)
                ranked.push({
                    entry: e,
                    tier: nameMatch ? 0 : 1
                });
        }

        ranked.sort((a, b) => a.tier - b.tier || UsageStore.score(b.entry.id) - UsageStore.score(a.entry.id) || a.entry.name.localeCompare(b.entry.name));
        return ranked.map(r => r.entry);
    }

    readonly property var searchPlaceholders: ({
        apps: "search applications…",
        games: "search games…",
        files: "search files…",
        system: ""
    })
    readonly property string searchPlaceholder: root.searchPlaceholders[LauncherState.activeTab] ?? ""

    // Nav contract every tab body may implement: moveLeft/moveRight/
    // moveUp/moveDown() -> bool (false on Left/Right = "nothing left to
    // move to, switch tabs" — Up/Down's return is unused, they just clamp)
    // and activate() for Enter. Applications has no Loader of its own, so
    // appsNav below is a plain QtObject implementing the same contract
    // over resultsList/searchInput directly. Games/Files/System resolve to
    // their Loader's loaded item.
    readonly property var activeTabItem: {
        switch (LauncherState.activeTab) {
        case "apps":
            return appsNav;
        case "games":
            return gamesLoader.item;
        case "files":
            return filesLoader.item;
        case "system":
            return systemLoader.item;
        default:
            return null;
        }
    }

    // Guards every nav-contract call: a tab whose content hasn't grown
    // that method yet (Files/System mid-rollout, before their own
    // Phase 2/3 passes land) falls back to `fallback` instead of throwing
    // "not a function" into the log, which the staging protocol treats as
    // a real regression. Extra arguments (beyond fnName/fallback) forward
    // straight through to the call -- handleKey(key) is the one nav-
    // contract method that isn't zero-arg.
    function callNav(fnName, fallback, ...args) {
        const nav = root.activeTabItem;
        if (nav && typeof nav[fnName] === "function")
            return nav[fnName](...args);
        return fallback;
    }

    // Applications' own nav-contract adapter. moveLeft/moveRight are
    // deliberately read-only probes — they report whether the caret has
    // room to move without moving it themselves, so the Left/Right key
    // handler below can leave `event.accepted` false and let TextInput's
    // own default caret handling apply. That's the one tab where the
    // caret is allowed to win; Games/Files/System hand Left/Right fully
    // to their own content instead, same as Games already did pre-Phase-1.
    QtObject {
        id: appsNav
        function moveLeft() {
            return searchInput.cursorPosition > 0;
        }
        function moveRight() {
            return searchInput.cursorPosition < searchInput.text.length;
        }
        function moveUp() {
            resultsList.currentIndex = Math.max(resultsList.currentIndex - 1, 0);
            return true;
        }
        function moveDown() {
            resultsList.currentIndex = Math.min(resultsList.currentIndex + 1, root.filteredEntries.length - 1);
            return true;
        }
        function activate() {
            root.launch(root.filteredEntries[resultsList.currentIndex]);
        }
    }

    // DesktopEntry.execute() currently ignores runInTerminal (Quickshell
    // 0.3.1 docs), so terminal apps are wrapped manually here — ghostty
    // matches the `terminal` value hyprland.nix already uses elsewhere.
    function launch(entry) {
        if (!entry)
            return;
        if (entry.runInTerminal)
            Quickshell.execDetached({
                command: ["ghostty", "-e", ...entry.command],
                workingDirectory: entry.workingDirectory
            });
        else
            entry.execute();
        UsageStore.recordLaunch(entry.id);
        LauncherState.hide();
    }

    // Click-outside-to-close backdrop. Declared before `box` so the box's
    // own (later-declared) MouseArea sits on top in hit-test order and
    // swallows clicks meant for the search field/results instead of letting
    // them fall through to this handler.
    MouseArea {
        anchors.fill: parent
        onClicked: LauncherState.hide()
    }

    // Elevation shadow-mimic: only rendered when the active theme opts in
    // (effect.popupElevated) — `float` leaves this fully transparent/
    // zero-offset so it's a no-op there, `slab` activates it.
    Rectangle {
        anchors.fill: box
        anchors.margins: -Theme.effect.popupShadowOffset
        radius: box.radius
        color: Theme.effect.popupElevated ? Theme.effect.popupShadowColor : "transparent"
        z: box.z - 1
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        // Applications stays narrow/centered (Spotlight-style); Games/Files/
        // Themes need real width for a grid or a two-pane browser.
        width: LauncherState.activeTab === "apps" ? Theme.spacing.launcherWidth : Theme.spacing.launcherWidthWide
        implicitHeight: content.implicitHeight + Theme.spacing.launcherPanelPadY
        radius: Theme.radius.panel
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        Behavior on width {
            NumberAnimation {
                duration: Theme.motion.hoverColor.duration
                easing.type: Theme.motion.hoverColor.easing
            }
        }

        MouseArea {
            anchors.fill: parent
            // No handler needed — an accepted-by-default MouseArea with no
            // onClicked is enough to stop the click from reaching the
            // backdrop below it.
        }

        Column {
            id: content
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            // Floating pill tabs, icon-only by default — hover or active
            // expands to icon+label (macOS-Spotlight-style, per the design
            // brief). Applications renders inline below; Games/Files/System
            // each get their own lazily-activated Loader further down.
            Row {
                spacing: Theme.spacing.launcherTabGap

                Repeater {
                    model: LauncherState.tabs

                    delegate: Rectangle {
                        id: tabPill
                        required property var modelData
                        readonly property bool isActive: LauncherState.activeTab === modelData.id
                        readonly property bool expanded: isActive || tabMouse.containsMouse

                        height: Theme.spacing.launcherTabHeight
                        // Clamped rather than a bare height / 2, so the
                        // baseline's 999 still reads as a pill while a theme
                        // can flatten it — ultraviolet-v2 asks for 3.
                        radius: Math.min(Theme.radius.tabPill, height / 2)
                        // Own token, not launcherItemSelectedBg: the active
                        // TAB is an inversion in the design system (solid
                        // fill, ground-coloured content) while a selected
                        // ROW is a translucent band, so the two can't share
                        // a value once a theme pulls them apart.
                        color: isActive ? Theme.color.launcherTabActiveBg : "transparent"
                        border.width: Theme.spacing.borderHairline
                        // accentPurple is base0C in both themes, which is
                        // also v2's invert-bg — so the active border needs
                        // no token of its own to land correctly in each.
                        border.color: isActive ? Theme.color.accentPurple : "transparent"
                        width: tabContent.implicitWidth + Theme.spacing.launcherTabPadX * 2

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.motion.hoverColor.duration
                                easing.type: Theme.motion.hoverColor.easing
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.motion.hoverColor.duration
                                easing.type: Theme.motion.hoverColor.easing
                            }
                        }

                        Row {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: tabPill.expanded ? Theme.spacing.launcherTabIconLabelGap : 0

                            Text {
                                text: tabPill.isActive ? tabPill.modelData.glyphFilled : tabPill.modelData.glyphOutline
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                                renderType: Text.NativeRendering
                                color: tabPill.isActive ? Theme.color.launcherTabActiveFg : Theme.color.rightModuleFg
                            }

                            // Wrapped in a clipping Item rather than binding
                            // the Text's own `width` to its own
                            // `implicitWidth` conditionally — that
                            // self-referential pattern intermittently
                            // triggered a "binding loop detected" warning
                            // under real layout churn (observed once other
                            // Loader-driven content nearby started
                            // resizing). Binding the *wrapper's* width to
                            // the inner Text's implicitWidth keeps the
                            // collapse-to-0 behavior without the loop,
                            // since the two properties now belong to
                            // different objects.
                            Item {
                                width: tabPill.expanded ? label.implicitWidth : 0
                                height: label.implicitHeight
                                clip: true

                                Text {
                                    id: label
                                    text: tabPill.modelData.label
                                    opacity: tabPill.expanded ? 1 : 0
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.sizeSmall
                                    color: tabPill.isActive ? Theme.color.launcherTabActiveFg : Theme.color.rightModuleFg

                                    Behavior on opacity {
                                        NumberAnimation { duration: Theme.motion.hoverColor.duration }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: LauncherState.setTab(tabPill.modelData.id)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Theme.spacing.launcherInputHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder
                // Driven by each tab's own `searchable` flag in
                // LauncherState.tabs rather than a hardcoded tab-id check
                // -- adding a tab is then genuinely one list entry, not a
                // second code path here too.
                readonly property bool currentTabSearchable: LauncherState.tabs.find(t => t.id === LauncherState.activeTab)?.searchable ?? false
                visible: currentTabSearchable

                Text {
                    visible: searchInput.text.length === 0 && root.searchPlaceholder.length > 0
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.searchPlaceholder
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                TextInput {
                    id: searchInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    onTextChanged: resultsList.currentIndex = 0
                    onAccepted: root.callNav("activate", undefined)

                    // Consults the active tab first -- Files uses this to
                    // close a context menu or clear a selection instead of
                    // the whole launcher closing out from under it
                    // (handleKey's other consumer, the window-level
                    // Shortcut above, only covers the prompt-focus case).
                    Keys.onEscapePressed: {
                        if (!root.callNav("handleKey", false, "Escape"))
                            LauncherState.hide();
                    }

                    // Delete/F2/Ctrl+C/Ctrl+X/Ctrl+V forward to the active
                    // tab's optional handleKey() -- a no-op everywhere
                    // except Files today, since handleKey is genuinely
                    // optional in the nav contract and callNav's fallback
                    // (false) means "not consumed" here too.
                    Keys.onPressed: (event) => {
                        const isDelete = event.key === Qt.Key_Delete;
                        const isF2 = event.key === Qt.Key_F2;
                        const isCtrlC = event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier);
                        const isCtrlX = event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier);
                        const isCtrlV = event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier);
                        const isCtrlH = event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier);
                        if (!(isDelete || isF2 || isCtrlC || isCtrlX || isCtrlV || isCtrlH))
                            return;
                        const name = isDelete ? "Delete" : isF2 ? "F2" : isCtrlC ? "Ctrl+C" : isCtrlX ? "Ctrl+X" : isCtrlV ? "Ctrl+V" : "Ctrl+H";
                        if (root.callNav("handleKey", false, name))
                            event.accepted = true;
                    }

                    // Up/Down always belong to the active tab's own content
                    // (never the hidden Applications list underneath, and
                    // never a tab switch — that's Left/Right's job below).
                    Keys.onUpPressed: (event) => {
                        root.callNav("moveUp", true);
                        event.accepted = true;
                    }
                    Keys.onDownPressed: (event) => {
                        root.callNav("moveDown", true);
                        event.accepted = true;
                    }

                    // Tab always cycles tabs -- a single-line search field
                    // has no other use for Tab (no multi-field focus chain
                    // to traverse here), so this is never ambiguous.
                    Keys.onTabPressed: (event) => {
                        LauncherState.nextTab();
                        event.accepted = true;
                    }
                    Keys.onBacktabPressed: (event) => {
                        LauncherState.prevTab();
                        event.accepted = true;
                    }

                    // Left/Right: routed through the active tab's own
                    // moveLeft/moveRight via the shared nav contract
                    // (GamesTab's flattened Recommended->Library->per-
                    // launcher index, Files' grid/tree, etc). Applications
                    // is the one exception — appsNav's moveLeft/moveRight
                    // are read-only caret-position probes, so leaving
                    // event.accepted false here lets TextInput's own
                    // default handling actually move the caret; every
                    // other tab hands Left/Right fully to its content
                    // instead. Either way, a false return means "nothing
                    // left to move to" and switches tabs, per Liam's own
                    // explicit ask ("if there is nothing to move forward or
                    // backwards for I should be able to use the arrow keys
                    // to switch tabs").
                    Keys.onLeftPressed: (event) => {
                        // Captured before the possible tab switch below --
                        // LauncherState.activeTab has already moved on to
                        // the neighbour tab by the time event.accepted is
                        // decided otherwise, which would silently flip
                        // Applications' caret carve-out on every boundary
                        // press.
                        const wasApps = LauncherState.activeTab === "apps";
                        const moved = root.callNav("moveLeft", false);
                        if (!moved)
                            LauncherState.prevTab();
                        event.accepted = wasApps ? moved : true;
                    }
                    Keys.onRightPressed: (event) => {
                        const wasApps = LauncherState.activeTab === "apps";
                        const moved = root.callNav("moveRight", false);
                        if (!moved)
                            LauncherState.nextTab();
                        event.accepted = wasApps ? moved : true;
                    }
                }
            }

            ListView {
                id: resultsList
                visible: LauncherState.activeTab === "apps"
                width: parent.width
                height: Math.min(contentHeight, Theme.spacing.launcherResultsMaxHeight)
                clip: true
                currentIndex: 0
                model: root.filteredEntries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    width: resultsList.width
                    height: Theme.spacing.launcherRowHeight
                    radius: Theme.radius.input
                    color: index === resultsList.currentIndex ? Theme.color.launcherItemSelectedBg : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.motion.hoverColor.duration
                            easing.type: Theme.motion.hoverColor.easing
                        }
                    }

                    Rectangle {
                        width: Theme.spacing.launcherIndicatorWidth
                        height: parent.height
                        color: row.index === resultsList.currentIndex ? Theme.color.accentPurple : "transparent"
                    }

                    ThemedIcon {
                        id: icon
                        anchors {
                            left: parent.left
                            leftMargin: Theme.spacing.launcherRowInset
                            verticalCenter: parent.verticalCenter
                        }
                        iconSize: Theme.spacing.launcherIconSize
                        // "application-x-executable" is the standard XDG
                        // fallback icon name — Quickshell.iconPath's third
                        // overload swaps to it automatically when an entry's
                        // own icon name doesn't resolve in the current theme,
                        // instead of rendering nothing.
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                    }

                    Text {
                        anchors {
                            left: icon.right
                            leftMargin: Theme.spacing.launcherIconLabelGap
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.modelData.name
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: resultsList.currentIndex = row.index
                        onClicked: root.launch(row.modelData)
                    }
                }
            }

            // Each tab's own Loader — `active` gating matters here
            // specifically because Games/Files spawn real background
            // Process calls (filesystem scans) that shouldn't run before
            // the user ever opens that tab, unlike the always-instantiated
            // Applications list above which has no such cost.
            //
            // No explicit height on the Loader itself — that was tried and
            // reverted after it turned out to actively fight the loaded
            // item's own sizing: Qt's Loader resizes the loaded item to
            // match the Loader's own size whenever the Loader has an
            // explicit size, so `height: item.height` created a real
            // feedback loop (item.height gets force-set to the Loader's
            // last value, which was 0 before the item existed, which then
            // permanently overrides — as a plain value, not a binding —
            // Column's own default "height follows implicitHeight"
            // behavior). Confirmed live: ThemesTab's `implicitHeight`
            // correctly computed 128 while `height` stayed stuck at 0.
            // Leaving the Loader unsized lets it do what it does by
            // default — follow the loaded item's real size — with `clip`
            // as a harmless safety net against overflow either way.
            //
            // `visible: active` alongside `active` itself: an inactive
            // Loader's *reported* height wasn't reliably snapping back to
            // 0 once its item was torn down (confirmed live — box.height
            // kept growing with each tab switched away from, as if a
            // previous tab's height lingered and stacked with the next
            // one's). Column excludes invisible children from its layout
            // sum entirely regardless of their reported size, which
            // sidesteps that question rather than depending on exactly
            // what an inactive Loader reports.
            Loader {
                id: gamesLoader
                width: parent.width
                clip: true
                active: LauncherState.activeTab === "games"
                visible: active
                sourceComponent: GamesTab {
                    searchQuery: searchInput.text
                }
            }

            Loader {
                id: filesLoader
                width: parent.width
                clip: true
                active: LauncherState.activeTab === "files"
                visible: active
                sourceComponent: FilesTab {
                    searchQuery: searchInput.text
                    // The rename/new-folder/new-file prompt is the one
                    // place in this module that steals active focus onto
                    // a second TextInput -- this hands back the means to
                    // restore it to the shared searchInput once that
                    // prompt closes, without Files needing a direct
                    // reference to it.
                    restoreFocus: () => searchInput.forceActiveFocus()
                }
            }

            Loader {
                id: systemLoader
                width: parent.width
                clip: true
                active: LauncherState.activeTab === "system"
                visible: active
                sourceComponent: SystemTab {
                    searchQuery: searchInput.text
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            searchInput.text = "";
            resultsList.currentIndex = 0;
            LauncherState.activeTab = "apps";
            searchInput.forceActiveFocus();
        }
    }
}
