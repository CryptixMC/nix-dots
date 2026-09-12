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

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            LauncherState.toggle();
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
        width: Theme.spacing.launcherWidth
        implicitHeight: content.implicitHeight + Theme.spacing.launcherPanelPadY
        radius: Theme.radius.panel
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

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

                            Text {
                                text: tabPill.modelData.label
                                width: tabPill.expanded ? implicitWidth : 0
                                opacity: tabPill.expanded ? 1 : 0
                                clip: true
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                                color: tabPill.isActive ? Theme.color.accentPurple : Theme.color.rightModuleFg

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.motion.hoverColor.duration }
                                }
                            }
                        }

                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
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

                Text {
                    visible: searchInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: "search applications…"
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

                    IconImage {
                        id: icon
                        anchors {
                            left: parent.left
                            leftMargin: Theme.spacing.launcherRowInset
                            verticalCenter: parent.verticalCenter
                        }
                        implicitSize: Theme.spacing.launcherIconSize
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
                        onEntered: resultsList.currentIndex = row.index
                        onClicked: root.launch(row.modelData)
                    }
                }
            }

            // Games/Files/Themes placeholder — real content designed but
            // not built this pass, see TODO.md.
            Text {
                width: parent.width
                visible: LauncherState.activeTab !== "apps"
                horizontalAlignment: Text.AlignHCenter
                topPadding: Theme.spacing.launcherContentGap
                bottomPadding: Theme.spacing.launcherContentGap
                text: "Coming soon"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
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
