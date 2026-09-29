import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"

// Lock / Logout / Suspend / Reboot / Shutdown. Only Reboot and Shutdown
// need confirmation; the others are trivially reversible.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property string confirmTarget: ""

    function run(command) {
        Quickshell.execDetached(["bash", "-lc", command]);
    }

    function requestConfirm(target) {
        root.confirmTarget = target;
    }

    function confirmed() {
        if (root.confirmTarget === "reboot")
            root.run("systemctl reboot");
        else if (root.confirmTarget === "shutdown")
            root.run("systemctl poweroff");
        root.confirmTarget = "";
    }

    component PowerButton: Rectangle {
        id: btn
        required property string label
        required property string glyph
        property bool danger: false
        signal activated

        width: parent.width
        height: Theme.spacing.launcherRowHeight + 6
        radius: Theme.radius.input
        color: mouse.containsMouse ? (btn.danger ? ThemeDefaults.alpha(Theme.color.accentPink, 0.15) : Theme.color.launcherItemSelectedBg) : Theme.color.launcherInputBg
        border.width: Theme.spacing.borderHairline
        border.color: btn.danger ? Theme.color.accentPink : Theme.color.accentPurple

        Behavior on color {
            ColorAnimation { duration: Theme.motion.hoverColor.duration }
        }

        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                text: btn.glyph
                renderType: Text.NativeRendering
                color: btn.danger ? Theme.color.accentPink : Theme.color.accentPurple
                font.pixelSize: Theme.font.sizeBase
            }
            Text {
                text: btn.label
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
            }
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
        spacing: 10
        visible: root.confirmTarget === ""

        Text {
            text: "Power"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }

        PowerButton {
            label: "Lock (unlock path never tested live — see TODO.md §5)"
            glyph: "⏼"
            onActivated: Quickshell.execDetached(["quickshell", "ipc", "-p", `${Quickshell.env("HOME")}/nix-dots/desktop/shell`, "call", "lock", "lock"])
        }
        PowerButton {
            label: "Log Out"
            glyph: "⏏"
            onActivated: root.run(`loginctl terminate-session "$XDG_SESSION_ID"`)
        }
        PowerButton {
            label: "Suspend"
            glyph: "⏾"
            onActivated: root.run("systemctl suspend")
        }
        PowerButton {
            label: "Reboot"
            glyph: "⟳"
            danger: true
            onActivated: root.requestConfirm("reboot")
        }
        PowerButton {
            label: "Shutdown"
            glyph: "⏻"
            danger: true
            onActivated: root.requestConfirm("shutdown")
        }
    }

    Column {
        width: parent.width
        spacing: 12
        visible: root.confirmTarget !== ""

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: `${root.confirmTarget === "reboot" ? "Reboot" : "Shut down"} now?`
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
            font.bold: true
        }

        Row {
            spacing: 8

            Rectangle {
                width: 90
                height: 32
                radius: Theme.radius.input
                color: yesMouse.containsMouse ? Theme.color.accentPink : "transparent"
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.accentPink
                Text {
                    anchors.centerIn: parent
                    text: "Confirm"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }
                MouseArea {
                    id: yesMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.confirmed()
                }
            }
            Rectangle {
                width: 90
                height: 32
                radius: Theme.radius.input
                color: noMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherBorder
                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }
                MouseArea {
                    id: noMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.confirmTarget = ""
                }
            }
        }
    }
}
