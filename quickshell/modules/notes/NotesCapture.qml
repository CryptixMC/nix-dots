import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// SUPER+N: quick manual "jot this down" capture, direct CLI invocation of
// the same capture_note() logic the notes-capture MCP server uses (see
// mcp-servers/notes_capture.py's --cli mode) -- one code path, two entry
// points, not a second implementation.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: NotesState.visible
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    onVisibleChanged: {
        if (visible) {
            titleInput.text = "";
            summaryInput.text = "";
            titleInput.forceActiveFocus();
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: NotesState.hide()
    }

    IpcHandler {
        target: "notes"
        function capture(): void {
            NotesState.toggle();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: NotesState.hide()
    }

    function submit() {
        if (titleInput.text.length === 0)
            return;
        captureProcess.command = ["qubi-notes-capture-mcp", "--cli", "--title", titleInput.text, "--summary", summaryInput.text];
        captureProcess.running = true;
    }

    Process {
        id: captureProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                NotesState.status = text.trim();
                NotesState.hide();
            }
        }
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Theme.spacing.notesPanelWidth + 160
        implicitHeight: content.implicitHeight + Theme.spacing.launcherPanelPadY * 2
        height: implicitHeight
        radius: Theme.radius.panel
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            Text {
                width: parent.width
                text: "Capture a note"
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

                Text {
                    visible: titleInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Title"
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                TextInput {
                    id: titleInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    Keys.onEscapePressed: NotesState.hide()
                    KeyNavigation.tab: summaryInput
                }
            }

            Rectangle {
                width: parent.width
                height: 90
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                Text {
                    visible: summaryInput.text.length === 0
                    anchors {
                        left: parent.left
                        top: parent.top
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    text: "Summary"
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                TextEdit {
                    id: summaryInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    wrapMode: TextEdit.WordWrap
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    Keys.onEscapePressed: NotesState.hide()
                }
            }

            Rectangle {
                width: 100
                height: Theme.spacing.clipboardRowHeight
                radius: Theme.radius.input
                color: submitMouse.containsMouse ? Theme.color.launcherItemSelectedBg : Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                Text {
                    anchors.centerIn: parent
                    text: "Capture"
                    color: Theme.color.accentPurple
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }

                MouseArea {
                    id: submitMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.submit()
                }
            }
        }
    }
}
