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
// instant. Colors/dimensions are a 1:1 copy of modules/home-manager/apps/
// walker.nix's walker/themes/float/style.css (see Colors.qml's launcher*
// tokens) — rail/grid modes aren't replicated, out of scope for this pass.
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
    Shortcut {
        sequence: "Escape"
        onActivated: LauncherState.hide()
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
        themes: ""
    })
    readonly property string searchPlaceholder: root.searchPlaceholders[LauncherState.activeTab] ?? ""

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
            // brief). Only "apps" drives real content below; the rest are
            // placeholders until their own passes (see TODO.md).
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
                        radius: height / 2
                        color: isActive ? Theme.color.launcherItemSelectedBg : "transparent"
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
                                text: tabPill.modelData.glyph
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                                renderType: Text.NativeRendering
                                color: tabPill.isActive ? Theme.color.accentPurple : Theme.color.rightModuleFg
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
                                    color: tabPill.isActive ? Theme.color.accentPurple : Theme.color.rightModuleFg

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
                // Themes tab has nothing to search (cycling/wallpaper picks
                // are click-driven, not text-filtered).
                visible: LauncherState.activeTab !== "themes"

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
                    onAccepted: root.launch(root.filteredEntries[resultsList.currentIndex])

                    Keys.onEscapePressed: LauncherState.hide()
                    Keys.onDownPressed: resultsList.currentIndex = Math.min(resultsList.currentIndex + 1, root.filteredEntries.length - 1)
                    Keys.onUpPressed: resultsList.currentIndex = Math.max(resultsList.currentIndex - 1, 0)
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
            // height/clip are both explicit rather than left to a Loader's
            // default auto-sizing: each tab's root Item sets `height`
            // (bounded via Math.min against launcherTabBodyMaxHeight) but
            // not `implicitHeight`, and a bare `Loader { width: ... }` with
            // no height override isn't guaranteed to follow the loaded
            // item's *explicit* height rather than its (here, unset/0)
            // implicitHeight — reading `item.height` directly sidesteps
            // that ambiguity, and `clip: true` is a belt-and-suspenders
            // guard against any tab's content ever visually overflowing
            // its own bounds regardless of the height binding.
            Loader {
                width: parent.width
                height: item ? item.height : 0
                clip: true
                active: LauncherState.activeTab === "themes"
                sourceComponent: ThemesTab {}
            }

            Loader {
                width: parent.width
                height: item ? item.height : 0
                clip: true
                active: LauncherState.activeTab === "games"
                sourceComponent: GamesTab {
                    searchQuery: searchInput.text
                }
            }

            Loader {
                width: parent.width
                height: item ? item.height : 0
                clip: true
                active: LauncherState.activeTab === "files"
                sourceComponent: FilesTab {
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
