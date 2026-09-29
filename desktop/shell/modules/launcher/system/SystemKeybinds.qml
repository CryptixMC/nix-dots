import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"
import ".."

// Reads ~/.config/hypr/keybinds.json, generated from hyprland.nix's bind
// list. `hyprctl binds -j` is useless under the Lua config backend (every
// bind reports as `__lua` with no description).
// watchChanges picks up a regenerated file without a restart.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property string searchQuery: ""

    property var binds: []
    property bool loaded: false
    property bool loadFailed: false

    FileView {
        path: `${Quickshell.env("HOME")}/.config/hypr/keybinds.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                root.binds = JSON.parse(text());
                root.loaded = true;
                root.loadFailed = false;
            } catch (e) {
                console.warn(`SystemKeybinds: failed to parse keybinds.json: ${e}`);
                root.binds = [];
                root.loaded = true;
                root.loadFailed = true;
            }
        }
        onLoadFailed: error => {
            root.binds = [];
            root.loaded = true;
            root.loadFailed = true;
        }
    }

    readonly property var filteredBinds: {
        const q = root.searchQuery.trim();
        if (q.length === 0)
            return root.binds;
        return Fuzzy.filterSort(q, root.binds, b => `${b.keys} ${b.desc}`);
    }

    readonly property var grouped: {
        const groups = {};
        const order = [];
        for (const b of root.filteredBinds) {
            const cat = b.cat ?? "Other";
            if (!groups[cat]) {
                groups[cat] = [];
                order.push(cat);
            }
            groups[cat].push(b);
        }
        return order.map(cat => ({
                    cat: cat,
                    items: groups[cat]
                }));
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Text {
            text: "Keybinds"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }

        Text {
            visible: root.loaded && root.loadFailed
            width: parent.width
            wrapMode: Text.Wrap
            text: "keybinds.json hasn't been generated yet -- run `nh home switch` to build it from hyprland.nix, then reopen this section (or leave it open, it picks up the change live)."
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Repeater {
            model: root.grouped

            delegate: Column {
                id: group
                required property var modelData
                width: column.width
                spacing: 4
                visible: group.modelData.items.length > 0

                Text {
                    text: group.modelData.cat
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }

                Repeater {
                    model: group.modelData.items

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: group.width
                        height: 26
                        radius: Theme.radius.input
                        color: "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 10

                            Rectangle {
                                width: keysText.implicitWidth + 14
                                height: 20
                                radius: Theme.radius.input
                                color: Theme.color.launcherInputBg
                                border.width: Theme.spacing.borderHairline
                                border.color: Theme.color.launcherBorder

                                Text {
                                    id: keysText
                                    anchors.centerIn: parent
                                    text: row.modelData.keys
                                    color: Theme.color.accentPurple
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.sizeSmall
                                }
                            }

                            Text {
                                text: row.modelData.desc
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
}
