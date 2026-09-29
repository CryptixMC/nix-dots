import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../../theme"
import "files"
import "games"
import "system"

// Launcher overlay: search box, app list and tabs, toggled over IPC from a
// Hyprland keybind (`quickshell ipc -p <dir> call launcher toggle`; -p must come
// before the subcommand). Runs in the bar's Quickshell instance so toggling is instant.
// Full-screen anchors host a click-outside-to-close backdrop; focusable for keyboard input.
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
    // Overlay so the launcher draws above fullscreen windows.
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    // Window-level Escape, since searchInput's handler doesn't fire when it's hidden
    // or another input has focus. Shortcut because PanelWindow isn't an Item (no Keys).
    // Disabled while a tab has a modal open, so Escape cancels the prompt instead of
    // closing the launcher.
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

    // Name matches rank above keyword/genericName/comment matches, then frecency,
    // then alphabetical. An empty query gives a pure frecency list.
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

    // Nav contract for tab bodies: moveLeft/moveRight/moveUp/moveDown() -> bool
    // (false on Left/Right means switch tabs) and activate() for Enter. Apps uses
    // appsNav below; other tabs resolve to their Loader's item.
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

    // Calls a nav-contract method if the tab implements it, else returns `fallback`.
    // Extra arguments are forwarded (handleKey takes the key).
    function callNav(fnName, fallback, ...args) {
        const nav = root.activeTabItem;
        if (nav && typeof nav[fnName] === "function")
            return nav[fnName](...args);
        return fallback;
    }

    // Apps nav adapter. moveLeft/moveRight only probe caret room without moving,
    // so the key handler can leave the event unaccepted and let TextInput move the caret.
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

    // DesktopEntry.execute() ignores runInTerminal, so terminal apps are wrapped
    // in ghostty manually.
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

    // Click-outside-to-close backdrop. Declared before `box` so the box's MouseArea
    // sits above it in hit-test order.
    MouseArea {
        anchors.fill: parent
        onClicked: LauncherState.hide()
    }

    // Elevation shadow, only rendered when the theme sets effect.popupElevated.
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
        // Apps stays narrow; other tabs need width for grids and two-pane views.
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
            // An accepted MouseArea with no handler stops clicks reaching the backdrop.
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

            // Pill tabs, icon-only unless hovered or active.
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
                        // Clamped so a theme can flatten the pill radius.
                        radius: Math.min(Theme.radius.tabPill, height / 2)
                        // Separate token from launcherItemSelectedBg: an active tab is a solid
                        // inversion while a selected row is a translucent band.
                        color: isActive ? Theme.color.launcherTabActiveBg : "transparent"
                        border.width: Theme.spacing.borderHairline
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

                            // Clipping wrapper sized to the Text's implicitWidth; binding the Text's own
                            // width to its implicitWidth caused binding-loop warnings.
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
                // Driven by each tab's `searchable` flag so a new tab is one list entry.
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

                    // Lets the active tab consume Escape (close a menu, clear selection) first.
                    Keys.onEscapePressed: {
                        if (!root.callNav("handleKey", false, "Escape"))
                            LauncherState.hide();
                    }

                    // Delete/F2/Ctrl+C/X/V go to the active tab's optional handleKey().
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

                    // Up/Down always go to the active tab's content.
                    Keys.onUpPressed: (event) => {
                        root.callNav("moveUp", true);
                        event.accepted = true;
                    }
                    Keys.onDownPressed: (event) => {
                        root.callNav("moveDown", true);
                        event.accepted = true;
                    }

                    Keys.onTabPressed: (event) => {
                        LauncherState.nextTab();
                        event.accepted = true;
                    }
                    Keys.onBacktabPressed: (event) => {
                        LauncherState.prevTab();
                        event.accepted = true;
                    }

                    // Left/Right go to the active tab's moveLeft/moveRight; a false return
                    // switches tabs. Apps leaves the event unaccepted so the caret still moves.
                    Keys.onLeftPressed: (event) => {
                        // Captured before the possible tab switch changes activeTab.
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
                        // Falls back to the XDG generic executable icon when the theme lacks the entry's icon.
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

            // `active` gating keeps Games/Files from scanning before their tab is opened.
            // Don't give the Loader an explicit height: Loader then force-sizes its item and
            // the item's height sticks at 0. `visible: active` because an inactive Loader's
            // reported height doesn't reliably return to 0, and Column skips invisible children.
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
                    // Lets Files return focus to searchInput after its prompt closes.
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
