import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Chat overlay talking to Goose over a persistent `goose acp` JSON-RPC
// session (GooseAcpSession.qml) — shown/hidden via IPC from a Hyprland
// keybind (same convention as Launcher.qml/ThemeState.qml — see
// hyprland.nix), not a resident always-visible surface. Structure/template
// is Launcher.qml (centered box, Overlay layer, click-outside-to-close,
// Escape-to-close); backend is genuinely new territory in this repo (see
// GooseAcpSession.qml's own header comment for what was confirmed live
// before this was written).
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: ChatState.visible
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

    Component.onCompleted: GooseAcpSession.start()

    readonly property var modelConfigOption: (GooseAcpSession.configOptions ?? []).find(c => c.id === "model") ?? null
    readonly property var providerConfigOption: (GooseAcpSession.configOptions ?? []).find(c => c.id === "provider") ?? null
    property bool modelPickerOpen: false

    function cycleMode() {
        const modes = GooseAcpSession.availableModes;
        if (modes.length === 0)
            return;
        const idx = modes.findIndex(m => m.id === GooseAcpSession.currentModeId);
        const next = modes[(idx + 1) % modes.length];
        GooseAcpSession.setMode(next.id);
    }

    function switchModel(modelValue) {
        const provider = root.providerConfigOption?.currentValue ?? "ollama";
        root.modelPickerOpen = false;
        GooseAcpSession.switchModel(provider, modelValue, () => {});
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ChatState.hide()
    }

    IpcHandler {
        target: "chat"
        function toggle(): void {
            ChatState.toggle();
        }
    }

    Connections {
        target: GooseAcpSession

        function onMessageChunk(text) {
            ChatState.appendToStreamingMessage(text);
        }

        function onThoughtChunk(text) {
            // Real AgentThoughtChunk content — model-dependent, only fires
            // for models that actually emit reasoning tokens (confirmed
            // live: qwen2.5-coder never does, others might). Rendered as
            // its own muted "thought" bubble rather than folded into the
            // reply text.
            ChatState.appendMessage("thought", text);
        }

        function onToolCall(call) {
            ChatState.appendMessage("tool", `→ ${call.title ?? call._meta?.goose?.toolCall?.toolName ?? "tool call"}`);
        }

        function onToolCallUpdate(update) {
            if (update.status === "completed")
                ChatState.appendMessage("tool", `✓ ${update.title ?? "tool"} completed`);
            else if (update.status === "failed")
                ChatState.appendMessage("tool", `✗ ${update.title ?? "tool"} failed`);
        }

        function onTurnComplete(result) {
            ChatState.streamingIndex = -1;
            if (result.stopReason === "error")
                ChatState.appendMessage("assistant", `(error: ${JSON.stringify(result.error)})`);
            const next = ChatState.dequeue();
            if (next !== undefined)
                root._startTurn(next);
        }

        function onPermissionRequested(request) {
            // Real approve/deny UI (see the banner in the input area
            // below) — only ever fires outside "auto" mode, confirmed
            // live (auto mode never sends a permission request at all).
            ChatState.pendingPermission = request;
        }

        function onSessionFailed(message) {
            console.warn("GooseAcpSession failed:", message);
            ChatState.appendMessage("assistant", `(goose acp error: ${message})`);
        }
    }

    function send(text) {
        if (text.trim().length === 0)
            return;
        // The user bubble is always shown immediately, whether or not a
        // turn is already in flight — only the actual dispatch to
        // GooseAcpSession waits its turn. _startTurn is never given
        // already-displayed text a second time (see onTurnComplete).
        ChatState.appendMessage("user", text);
        if (!GooseAcpSession.sessionReady || GooseAcpSession.busy) {
            ChatState.enqueue(text);
            return;
        }
        root._startTurn(text);
    }

    function _startTurn(text) {
        ChatState.streamingIndex = ChatState.appendMessage("assistant", "");
        GooseAcpSession.prompt(text);
    }

    // Same `wl-copy` the screenshot keybinds in hyprland.nix already use —
    // as a positional argument, not piped stdin, so a fresh one-shot
    // Quickshell.execDetached call per click is enough (no persistent
    // Process to accidentally reuse while a previous wl-copy is still
    // alive serving the last selection).
    function copyToClipboard(text) {
        Quickshell.execDetached({
            command: ["wl-copy", text]
        });
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ChatState.hide()
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Theme.spacing.launcherWidthWide
        height: Math.min(parent.height * 0.75, 720)
        radius: Theme.radius.panel
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
            // Swallow clicks so the backdrop behind doesn't close the chat.
        }

        Column {
            anchors {
                fill: parent
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            Row {
                id: headerRow
                width: parent.width
                height: Theme.spacing.themePillHeight
                spacing: Theme.spacing.themePillGap

                Rectangle {
                    width: modeLabel.implicitWidth + Theme.spacing.themePillPadX * 2
                    height: parent.height
                    radius: height / 2
                    color: Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherInputBorder

                    Text {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: `mode: ${GooseAcpSession.currentModeId}`
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.cycleMode()
                    }
                }

                Rectangle {
                    width: modelLabel.implicitWidth + Theme.spacing.themePillPadX * 2
                    height: parent.height
                    radius: height / 2
                    color: Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherInputBorder

                    Text {
                        id: modelLabel
                        anchors.centerIn: parent
                        text: `model: ${root.modelConfigOption?.currentValue ?? "?"}`
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.modelPickerOpen = !root.modelPickerOpen
                    }
                }
            }

            Column {
                id: modelPickerColumn
                visible: root.modelPickerOpen
                width: parent.width
                spacing: Theme.spacing.themePillGap / 2

                Repeater {
                    model: root.modelConfigOption?.options ?? []

                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: Theme.spacing.launcherRowHeight
                        radius: Theme.radius.input
                        color: modelData.value === root.modelConfigOption?.currentValue ? Theme.color.launcherItemSelectedBg : "transparent"

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                margins: Theme.spacing.launcherRowInset
                            }
                            text: modelData.name
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.switchModel(modelData.value)
                        }
                    }
                }
            }

            ListView {
                id: messageList
                width: parent.width
                height: parent.height - headerRow.height - parent.spacing - (modelPickerColumn.visible ? modelPickerColumn.height + parent.spacing : 0) - (permissionBanner.visible ? permissionBanner.height + parent.spacing : 0) - inputBox.height - parent.spacing
                clip: true
                model: ChatState.messages
                spacing: Theme.spacing.launcherContentGap / 2

                onCountChanged: positionViewAtEnd()

                delegate: Rectangle {
                    id: bubble
                    required property var modelData
                    readonly property bool isUser: modelData.role === "user"
                    readonly property bool isTool: modelData.role === "tool"
                    readonly property bool isThought: modelData.role === "thought"
                    readonly property bool isMuted: isTool || isThought

                    width: messageList.width
                    height: text.implicitHeight + (bubble.isMuted ? 0 : meta.height) + Theme.spacing.launcherContentGap
                    radius: Theme.radius.input
                    color: isMuted ? "transparent" : (isUser ? Theme.color.launcherItemSelectedBg : Theme.color.launcherInputBg)

                    Text {
                        id: text
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: Theme.spacing.launcherRowInset
                        }
                        text: bubble.isTool ? bubble.modelData.text : bubble.isThought ? `thinking: ${bubble.modelData.text}` : (bubble.isUser ? "you: " : "goose: ") + bubble.modelData.text
                        wrapMode: Text.Wrap
                        color: bubble.isMuted ? Theme.color.launcherPlaceholderFg : Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: bubble.isMuted ? Theme.font.sizeSmall : Theme.font.sizeBase
                        font.italic: bubble.isMuted
                    }

                    Row {
                        id: meta
                        visible: !bubble.isMuted
                        anchors {
                            left: parent.left
                            top: text.bottom
                            margins: Theme.spacing.launcherRowInset
                        }
                        height: visible ? implicitHeight : 0
                        spacing: Theme.spacing.launcherContentGap

                        Text {
                            text: bubble.modelData.time ? new Date(bubble.modelData.time).toLocaleTimeString(Qt.locale(), "hh:mm") : ""
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        Text {
                            text: "copy"
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.underline: copyArea.containsMouse

                            MouseArea {
                                id: copyArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.copyToClipboard(bubble.modelData.text)
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: permissionBanner
                visible: ChatState.pendingPermission !== null
                width: parent.width
                height: visible ? implicitHeight : 0
                implicitHeight: permissionColumn.implicitHeight + Theme.spacing.launcherContentGap
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.accentPurple

                Column {
                    id: permissionColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Theme.spacing.launcherRowInset
                    }
                    spacing: Theme.spacing.launcherContentGap / 2

                    Text {
                        width: parent.width
                        text: `goose wants to: ${permissionBanner.visible ? (ChatState.pendingPermission.params?.toolCall?.title ?? "run a tool") : ""}`
                        wrapMode: Text.Wrap
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    Row {
                        spacing: Theme.spacing.launcherContentGap

                        Repeater {
                            model: permissionBanner.visible ? (ChatState.pendingPermission.params?.options ?? []) : []

                            delegate: Rectangle {
                                required property var modelData
                                width: optionLabel.implicitWidth + Theme.spacing.themePillPadX * 2
                                height: Theme.spacing.themePillHeight
                                radius: height / 2
                                color: Theme.color.launcherItemSelectedBg
                                border.width: Theme.spacing.borderHairline
                                border.color: Theme.color.launcherInputBorder

                                Text {
                                    id: optionLabel
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: Theme.color.fg
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.sizeSmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const req = ChatState.pendingPermission;
                                        GooseAcpSession.respondToPermission(req.id, modelData.optionId);
                                        ChatState.pendingPermission = null;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: inputBox
                width: parent.width
                height: Theme.spacing.launcherInputHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: GooseAcpSession.busy ? Theme.color.accentPurple : Theme.color.launcherInputBorder

                Text {
                    visible: chatInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: !GooseAcpSession.sessionReady ? "starting goose…" : GooseAcpSession.busy ? "goose is thinking… (you can keep typing)" : "message goose…"
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                TextInput {
                    id: chatInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    Keys.onEscapePressed: ChatState.hide()
                    onAccepted: {
                        root.send(text);
                        text = "";
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible)
            chatInput.forceActiveFocus();
    }
}
