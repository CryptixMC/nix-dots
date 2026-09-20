import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// SUPER+SHIFT+D: side-by-side model compare, two fully independent
// `goose acp` processes (GooseAcpPane.qml, new/own file -- see its header
// for why GooseAcpSession.qml itself is untouched here). One shared prompt
// goes to both panes at once; each pane streams its own response
// independently so slow/fast models don't block each other.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: ChatCompareState.visible
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
            if (!paneLeft.sessionReady && !paneLeft.busy)
                paneLeft.start();
            if (!paneRight.sessionReady && !paneRight.busy)
                paneRight.start();
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ChatCompareState.hide()
    }

    GooseAcpPane {
        id: paneLeft
        provider: "ollama"
        model: "qwen3.6:latest"
        onMessageChunk: text => leftText.text += text
        onSessionFailed: msg => leftText.text += `\n[error: ${msg}]`
    }

    GooseAcpPane {
        id: paneRight
        provider: "ollama"
        model: "qwen3-coder:latest"
        onMessageChunk: text => rightText.text += text
        onSessionFailed: msg => rightText.text += `\n[error: ${msg}]`
    }

    function sendToBoth() {
        const text = promptInput.text;
        if (text.length === 0)
            return;
        leftText.text = "";
        rightText.text = "";
        promptInput.text = "";
        if (paneLeft.sessionReady)
            paneLeft.prompt(text);
        if (paneRight.sessionReady)
            paneRight.prompt(text);
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, 1100)
        height: Math.min(parent.height * 0.85, 700)
        radius: Theme.radius.panel
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors {
                fill: parent
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            Row {
                width: parent.width
                height: parent.height - promptRow.height - parent.spacing
                spacing: Theme.spacing.compareColumnGap

                Rectangle {
                    width: (parent.width - Theme.spacing.compareColumnGap) / 2
                    height: parent.height
                    radius: Theme.radius.input
                    color: Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherInputBorder

                    Column {
                        anchors {
                            fill: parent
                            margins: Theme.spacing.launcherContentInset
                        }
                        spacing: 4

                        Text {
                            text: `${paneLeft.provider}: ${paneLeft.model}${paneLeft.busy ? " (thinking…)" : ""}`
                            color: Theme.color.accentPurple
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.bold: true
                        }
                        Flickable {
                            width: parent.width
                            height: parent.height - 24
                            contentHeight: leftText.implicitHeight
                            clip: true
                            Text {
                                id: leftText
                                width: parent.width
                                wrapMode: Text.WordWrap
                                textFormat: Text.MarkdownText
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - Theme.spacing.compareColumnGap) / 2
                    height: parent.height
                    radius: Theme.radius.input
                    color: Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherInputBorder

                    Column {
                        anchors {
                            fill: parent
                            margins: Theme.spacing.launcherContentInset
                        }
                        spacing: 4

                        Text {
                            text: `${paneRight.provider}: ${paneRight.model}${paneRight.busy ? " (thinking…)" : ""}`
                            color: Theme.color.accentPurple
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.bold: true
                        }
                        Flickable {
                            width: parent.width
                            height: parent.height - 24
                            contentHeight: rightText.implicitHeight
                            clip: true
                            Text {
                                id: rightText
                                width: parent.width
                                wrapMode: Text.WordWrap
                                textFormat: Text.MarkdownText
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: promptRow
                width: parent.width
                height: Theme.spacing.launcherInputHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                TextInput {
                    id: promptInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    Keys.onEscapePressed: ChatCompareState.hide()
                    onAccepted: root.sendToBoth()
                }
            }
        }
    }
}
