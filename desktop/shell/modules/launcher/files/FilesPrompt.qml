import QtQuick
import "../../../theme"

// Inline prompt for Rename / New Folder / New File (no native dialogs in a
// layer-shell popup). Takes focus while open; `restoreFocus` hands it back to
// Launcher.qml's searchInput on close.
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 600

    property string title: ""
    property var onConfirm: null
    property var onCancel: null
    property var restoreFocus: null

    function open(promptTitle, initialValue, confirmFn, cancelFn) {
        root.title = promptTitle;
        root.onConfirm = confirmFn ?? null;
        root.onCancel = cancelFn ?? null;
        root.visible = true;
        field.text = initialValue ?? "";
        field.forceActiveFocus();
        field.selectAll();
    }

    function close() {
        root.visible = false;
        root.onConfirm = null;
        root.onCancel = null;
        if (root.restoreFocus)
            root.restoreFocus();
    }

    function cancel() {
        const cb = root.onCancel;
        root.close();
        if (cb)
            cb();
    }

    function confirm() {
        const cb = root.onConfirm;
        const text = field.text.trim();
        root.close();
        if (cb && text.length > 0)
            cb(text);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancel()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(360, parent.width - 40)
        height: promptColumn.implicitHeight + 24
        radius: Theme.radius.popup
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.accentPurple

        MouseArea {
            anchors.fill: parent
            // Swallows clicks so they don't reach the cancel backdrop.
        }

        Column {
            id: promptColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 8

            Text {
                text: root.title
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: Theme.spacing.launcherInputHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                TextInput {
                    id: field
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    Keys.onReturnPressed: root.confirm()
                    Keys.onEnterPressed: root.confirm()
                    Keys.onEscapePressed: root.cancel()
                }
            }
        }
    }
}
