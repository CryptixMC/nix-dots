import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"

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
        width: QubiTheme.spacing.notesPanelWidth + 160
        implicitHeight: content.implicitHeight + QubiTheme.spacing.launcherPanelPadY * 2
        height: implicitHeight
        radius: QubiTheme.radius.panel
        color: QubiTheme.color.launcherBg
        border.width: QubiTheme.spacing.borderHairline
        border.color: QubiTheme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: QubiTheme.spacing.launcherContentInset
            }
            spacing: QubiTheme.spacing.launcherContentGap

            Text {
                width: parent.width
                text: "Capture a note"
                color: QubiTheme.color.fg
                font.family: QubiTheme.font.family
                font.pixelSize: QubiTheme.font.sizeBase
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: QubiTheme.spacing.launcherInputHeight
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.launcherInputBorder

                Text {
                    visible: titleInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: QubiTheme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Title"
                    color: QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeBase
                }

                TextInput {
                    id: titleInput
                    anchors {
                        fill: parent
                        margins: QubiTheme.spacing.launcherInputTextInset
                    }
                    color: QubiTheme.color.fg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeBase
                    Keys.onEscapePressed: NotesState.hide()
                    KeyNavigation.tab: summaryInput
                }
            }

            Rectangle {
                width: parent.width
                height: 90
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.launcherInputBorder

                Text {
                    visible: summaryInput.text.length === 0
                    anchors {
                        left: parent.left
                        top: parent.top
                        margins: QubiTheme.spacing.launcherInputTextInset
                    }
                    text: "Summary"
                    color: QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeBase
                }

                TextEdit {
                    id: summaryInput
                    anchors {
                        fill: parent
                        margins: QubiTheme.spacing.launcherInputTextInset
                    }
                    wrapMode: TextEdit.WordWrap
                    color: QubiTheme.color.fg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeBase
                    Keys.onEscapePressed: NotesState.hide()
                }
            }

            Rectangle {
                width: 100
                height: QubiTheme.spacing.clipboardRowHeight
                radius: QubiTheme.radius.input
                color: submitMouse.containsMouse ? QubiTheme.color.launcherItemSelectedBg : QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.launcherInputBorder

                Text {
                    anchors.centerIn: parent
                    text: "Capture"
                    color: QubiTheme.color.accentPurple
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeSmall
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
