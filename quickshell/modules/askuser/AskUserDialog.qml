import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Surfaces ask-user MCP tool calls (mcp-servers/ask_user.py) as a real
// blocking on-screen dialog. Structural cousin of ClipboardTransform.qml.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: AskUserState.visible
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

    IpcHandler {
        target: "askuser"
        function show(requestId: string): void {
            root._requestId = requestId;
            readRequestProcess.running = true;
        }
    }

    property string _requestId: ""

    Process {
        id: readRequestProcess
        command: ["cat", `${Quickshell.env("HOME")}/.local/share/qubi/ask-user/request-${root._requestId}.json`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const req = JSON.parse(text);
                    AskUserState.requestId = req.id;
                    AskUserState.question = req.question;
                    AskUserState.options = req.options ?? [];
                    AskUserState.allowFreeText = req.allow_free_text ?? true;
                    AskUserState.responseFile = req.response_file;
                    freeTextInput.text = "";
                    AskUserState.visible = true;
                } catch (e) {
                    console.warn("AskUserDialog: failed to read request", e);
                }
            }
        }
    }

    function respond(answer) {
        writeResponseProcess.command = ["bash", "-c", `printf '%s' "$1" > "$2"`, "bash",
            JSON.stringify({ answer: answer }), AskUserState.responseFile];
        writeResponseProcess.running = true;
        AskUserState.reset();
    }

    Process {
        id: writeResponseProcess
        running: false
    }

    Shortcut {
        sequence: "Escape"
        onActivated: AskUserState.reset()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: AskUserState.reset()
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Theme.spacing.clipboardPanelWidth
        implicitHeight: content.implicitHeight + Theme.spacing.launcherPanelPadY * 2
        height: Math.min(implicitHeight, parent.height * 0.8)
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
                text: "Qubi is asking…"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: AskUserState.question
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                font.bold: true
            }

            Column {
                width: parent.width
                spacing: 2

                Repeater {
                    model: AskUserState.options
                    delegate: Rectangle {
                        id: optRow
                        required property string modelData
                        width: content.width
                        height: Theme.spacing.clipboardRowHeight
                        radius: Theme.radius.input
                        color: optMouse.containsMouse ? Theme.color.launcherItemSelectedBg : Theme.color.launcherInputBg
                        border.width: Theme.spacing.borderHairline
                        border.color: Theme.color.launcherInputBorder

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                margins: Theme.spacing.launcherRowInset
                            }
                            text: optRow.modelData
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        MouseArea {
                            id: optMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.respond(optRow.modelData)
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
                visible: AskUserState.allowFreeText

                Text {
                    visible: freeTextInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Type an answer…"
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                TextInput {
                    id: freeTextInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    Keys.onEscapePressed: AskUserState.reset()
                    onAccepted: if (text.length > 0) root.respond(text)
                }
            }
        }
    }
}
