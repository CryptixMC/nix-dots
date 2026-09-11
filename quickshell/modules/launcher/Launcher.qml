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

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Colors.launcherWidth
        implicitHeight: content.implicitHeight + 20
        radius: 8
        color: Colors.launcherBg
        border.width: 1
        border.color: Colors.launcherBorder

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
                margins: 10
            }
            spacing: 8

            Rectangle {
                width: parent.width
                height: 36
                radius: 4
                color: Colors.launcherInputBg
                border.width: 1
                border.color: Colors.launcherInputBorder

                Text {
                    visible: searchInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: 11
                        verticalCenter: parent.verticalCenter
                    }
                    text: "search applications…"
                    color: Colors.launcherPlaceholderFg
                    font.family: Colors.fontFamily
                    font.pixelSize: Colors.fontSizeBase
                }

                TextInput {
                    id: searchInput
                    anchors {
                        fill: parent
                        margins: 9
                    }
                    color: Colors.fg
                    font.family: Colors.fontFamily
                    font.pixelSize: Colors.fontSizeBase

                    onTextChanged: resultsList.currentIndex = 0
                    onAccepted: root.launch(root.filteredEntries[resultsList.currentIndex])

                    Keys.onEscapePressed: LauncherState.hide()
                    Keys.onDownPressed: resultsList.currentIndex = Math.min(resultsList.currentIndex + 1, root.filteredEntries.length - 1)
                    Keys.onUpPressed: resultsList.currentIndex = Math.max(resultsList.currentIndex - 1, 0)
                }
            }

            ListView {
                id: resultsList
                width: parent.width
                height: Math.min(contentHeight, 360)
                clip: true
                currentIndex: 0
                model: root.filteredEntries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    width: resultsList.width
                    height: 34
                    radius: 4
                    color: index === resultsList.currentIndex ? Colors.launcherItemSelectedBg : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 180
                            easing.type: Easing.OutQuad
                        }
                    }

                    Rectangle {
                        width: 2
                        height: parent.height
                        color: row.index === resultsList.currentIndex ? Colors.accentPurple : "transparent"
                    }

                    IconImage {
                        id: icon
                        anchors {
                            left: parent.left
                            leftMargin: 11
                            verticalCenter: parent.verticalCenter
                        }
                        implicitSize: Colors.launcherIconSize
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
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.modelData.name
                        color: Colors.fg
                        font.family: Colors.fontFamily
                        font.pixelSize: Colors.fontSizeBase
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: resultsList.currentIndex = row.index
                        onClicked: root.launch(row.modelData)
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            searchInput.text = "";
            resultsList.currentIndex = 0;
            searchInput.forceActiveFocus();
        }
    }
}
