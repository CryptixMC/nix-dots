import QtQuick
import "../../theme"

// Every edit PackageOps has made this session (and across restarts --
// pending.json survives them), with a Revert per entry and a Rebuild
// shortcut once you're happy with the set. Empty state matters here more
// than most lists: "nothing pending" is the common case and should read as
// reassuring, not blank.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property int _rebuildJobId: -1

    function rebuild(scope) {
        // No explicit cwd -- matches SystemAbout.qml's identical nh
        // invocations, which don't need one either (nh finds the flake on
        // its own). System scope goes through pkexec like the OS update
        // button there, for the same reason: nixos-rebuild's own internal
        // sudo step has nowhere to prompt inside a piped Process.
        const argv = scope === "user" ? ["nh", "home", "switch"] : ["nh", "os", "switch"];
        root._rebuildJobId = JobRunner.run(`Rebuild (${scope})`, argv, { privileged: scope !== "user" });
        SystemState.activeSection = "jobs";
    }

    component ActionButton: Rectangle {
        id: btn
        required property string label
        signal activated
        width: label_.implicitWidth + 16
        height: 22
        radius: Theme.radius.input
        color: mouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        Text {
            id: label_
            anchors.centerIn: parent
            text: btn.label
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Text {
            visible: PackageOps.pending.length === 0
            text: "Nothing pending -- \"Add to config\" entries from the Packages tab show up here before you rebuild."
            wrapMode: Text.Wrap
            width: parent.width
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Row {
            visible: PackageOps.pending.length > 0
            spacing: 8
            ActionButton { label: "rebuild home"; onActivated: root.rebuild("user") }
            ActionButton { label: "rebuild system (needs auth)"; onActivated: root.rebuild("system") }
        }

        Repeater {
            model: PackageOps.pending

            delegate: Row {
                required property var modelData
                width: column.width
                height: 24
                spacing: 8

                Text { width: 140; elide: Text.ElideRight; text: modelData.attr; color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall; font.bold: true }
                Text { width: 260; elide: Text.ElideRight; text: modelData.file; color: Theme.color.launcherPlaceholderFg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                Text {
                    width: column.width - 140 - 260 - 70 - 24
                    text: new Date(modelData.timestamp).toLocaleString(Qt.locale(), "MMM d, HH:mm")
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }
                ActionButton {
                    label: "revert"
                    onActivated: PackageOps.revert(modelData, (ok, message) => {
                        if (!ok)
                            console.warn(`InstallPending: revert "${modelData.attr}" failed -- ${message}`);
                    })
                }
            }
        }
    }
}
