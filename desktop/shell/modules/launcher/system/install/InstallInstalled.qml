import QtQuick
import "../../../../theme"

// Read-only browse of PackageDeclarations' results, grouped by scope.
// Topical-site entries are shown marked read-only so it's clear where
// they're declared.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    readonly property var userPkgs: PackageDeclarations.declared.filter(d => d.scope === "user" && !d.readOnly).sort((a, b) => a.attr.localeCompare(b.attr))
    readonly property var systemPkgs: PackageDeclarations.declared.filter(d => d.scope === "system" && !d.readOnly).sort((a, b) => a.attr.localeCompare(b.attr))
    readonly property var readOnlyPkgs: PackageDeclarations.declared.filter(d => d.readOnly).sort((a, b) => a.attr.localeCompare(b.attr))

    component Group: Column {
        id: group
        required property string title
        required property var items
        width: parent.width
        spacing: 4

        Text {
            text: `${group.title} (${group.items.length})`
            font.bold: true
            font.pixelSize: 13
            color: Theme.color.fg
            font.family: Theme.font.family
        }

        Flow {
            width: parent.width
            spacing: 6

            Repeater {
                model: group.items

                delegate: Rectangle {
                    required property var modelData
                    height: 22
                    radius: Theme.radius.input
                    color: ThemeDefaults.alpha(Theme.base16.base02, 0.5)
                    width: chipLabel.implicitWidth + 16

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: modelData.attr
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                }
            }
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 16

        Text {
            visible: !PackageDeclarations.loaded
            text: "Reading declared packages…"
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Group { title: "User (home-manager)"; items: root.userPkgs }
        Group { title: "System (NixOS)"; items: root.systemPkgs }
        Group { title: "Declared elsewhere (read-only)"; items: root.readOnlyPkgs }
    }
}
