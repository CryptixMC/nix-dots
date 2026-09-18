import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Chat overlay talking to Qubi over a persistent `goose acp` JSON-RPC
// session (GooseAcpSession.qml) — shown/hidden via IPC from a Hyprland
// keybind (same convention as Launcher.qml/ThemeState.qml — see
// hyprland.nix). Backend is GooseAcpSession.qml (see its own header
// comment for what was confirmed live before this was written).
//
// Right-docked sliding panel (not a centered, full-screen-blocking
// overlay like Launcher.qml/SessionsPicker.qml) — the surface itself is
// only Theme.spacing.chatPanelWidth wide, anchored top+bottom+right, so
// the rest of the desktop stays fully interactive while it's open. Closes
// via Escape, the header's own close button, or pressing the toggle
// keybind again — no click-outside-to-close, since there's no full-screen
// backdrop to click through.
//
// The slide-in/out is genuinely animated, not just visible-toggled: the
// PanelWindow itself stays mapped (root.panelMapped) for the duration of
// the close animation (closeTimer), unmapping only once it's had time to
// finish — otherwise a layer-shell surface just vanishes instantly with
// no transition to animate. panel.x is a plain live binding to
// ChatState.visible with a Behavior — this animates correctly on every
// open/close including the first, since Behavior only skips animating a
// property's very first-ever assignment (component construction, while
// still closed), not subsequent binding re-evaluations.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: root.panelMapped
    focusable: true

    property bool panelMapped: false

    Connections {
        target: ChatState
        function onVisibleChanged() {
            if (ChatState.visible)
                root.panelMapped = true;
            else
                closeTimer.restart();
        }
    }

    Timer {
        id: closeTimer
        interval: Theme.motion.chatSlide.duration
        onTriggered: root.panelMapped = false
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    // Without this, the bar's own exclusive zone (reserved top-of-screen
    // space) shrinks this window's usable area from underneath it, so a
    // panel anchored top+bottom (touching both screen edges, unlike a
    // smaller centered dialog) ends up taller than the actually-available
    // space and its bottom edge hangs off-screen -- confirmed as a real,
    // reported bug. `Ignore` makes this window's geometry the true full
    // screen regardless of what other layer-shell surfaces reserve.
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    Component.onCompleted: GooseAcpSession.start()

    readonly property var modelConfigOption: (GooseAcpSession.configOptions ?? []).find(c => c.id === "model") ?? null
    readonly property var providerConfigOption: (GooseAcpSession.configOptions ?? []).find(c => c.id === "provider") ?? null
    property bool modelPickerOpen: false
    property bool subagentPickerOpen: false

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

    function switchSubagentModel(modelValue) {
        const provider = root.providerConfigOption?.currentValue ?? "ollama";
        root.subagentPickerOpen = false;
        GooseAcpSession.switchSubagentModel(provider, modelValue, () => {});
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
        // SUPER+SHIFT+D (already reserved in hyprland.nix, calls
        // `chat compare`) -- ChatCompare.qml is its own file/overlay with
        // two independent GooseAcpPane processes, not part of this
        // singleton's own session.
        function compare(): void {
            ChatCompareState.toggle();
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
            // reply text. Streamed into a single bubble the same way
            // onMessageChunk streams the reply -- these chunks arrive in
            // small pieces, and appendMessage-per-chunk was confirmed live
            // to render one bubble per word instead of one growing bubble.
            if (ChatState.streamingThoughtIndex < 0)
                ChatState.streamingThoughtIndex = ChatState.appendMessage("thought", text);
            else
                ChatState.appendToStreamingMessage(text, ChatState.streamingThoughtIndex);
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
            ChatState.streamingThoughtIndex = -1;
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
            ChatState.appendMessage("assistant", `(qubi error: ${message})`);
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

    function regenerate() {
        var lastIdx = 0;
        for (var i = ChatState.messages.length - 1; i >= 0; --i)
            if (ChatState.messages[i].role === "user") {
                lastIdx = i;
                break;
            }
        if (ChatState.messages[lastIdx].role !== "user")
            return;
        ChatState.messages = ChatState.messages.slice(0, lastIdx + 1);
        root._startTurn(ChatState.messages[lastIdx].text);
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

    function sendFromInput() {
        root.send(chatInput.text);
        chatInput.text = "";
    }

    Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Theme.spacing.chatPanelWidth
        x: ChatState.visible ? 0 : width
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        Behavior on x {
            NumberAnimation {
                duration: Theme.motion.chatSlide.duration
                easing.type: Theme.motion.chatSlide.easing
            }
        }

        MouseArea {
            anchors.fill: parent
            // Swallow clicks — same defensive precedent as the old
            // centered-box overlay, harmless here since there's no
            // backdrop behind this panel to accidentally click through to.
        }

        Column {
            id: content
            anchors {
                fill: parent
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            Row {
                id: headerRow
                width: parent.width
                height: Theme.spacing.chatHeaderHeight

                Text {
                    id: titleLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Qubi"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    font.bold: true
                }

                Item {
                    width: parent.width - titleLabel.width - closeButton.width
                    height: 1
                }

                Rectangle {
                    id: closeButton
                    width: Theme.spacing.chatCloseSize
                    height: Theme.spacing.chatCloseSize
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: closeArea.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: ChatState.hide()
                    }
                }
            }

            Flow {
                id: statusPillsRow
                width: parent.width
                spacing: Theme.spacing.themePillGap

                Rectangle {
                    width: modeLabel.implicitWidth + Theme.spacing.themePillPadX * 2
                    height: Theme.spacing.themePillHeight
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
                    height: Theme.spacing.themePillHeight
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

                Rectangle {
                    width: subagentLabel.implicitWidth + Theme.spacing.themePillPadX * 2
                    height: Theme.spacing.themePillHeight
                    radius: height / 2
                    color: Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherInputBorder

                    Text {
                        id: subagentLabel
                        anchors.centerIn: parent
                        text: `subagent: ${GooseAcpSession.subagentModel || "none"}`
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.subagentPickerOpen = !root.subagentPickerOpen
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

            Column {
                id: subagentPickerColumn
                visible: root.subagentPickerOpen
                width: parent.width
                spacing: Theme.spacing.themePillGap / 2

                Repeater {
                    model: root.modelConfigOption?.options ?? []

                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: Theme.spacing.launcherRowHeight
                        radius: Theme.radius.input
                        color: modelData.value === GooseAcpSession.subagentModel ? Theme.color.launcherItemSelectedBg : "transparent"

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
                            onClicked: root.switchSubagentModel(modelData.value)
                        }
                    }
                }
            }

            ListView {
                id: messageList
                width: parent.width
                // statusPillsRow (mode/model/subagent) was missing from this
                // subtraction entirely -- a real, reported bug: the whole
                // column silently overflowed the panel's bottom edge by
                // exactly that row's height, cropping the input bar and
                // send button off-screen. Every other sibling in `content`
                // was already accounted for here; this one just didn't
                // have an id to reference until now.
                height: parent.height - headerRow.height - parent.spacing - statusPillsRow.height - parent.spacing - (modelPickerColumn.visible ? modelPickerColumn.height + parent.spacing : 0) - (subagentPickerColumn.visible ? subagentPickerColumn.height + parent.spacing : 0) - (permissionBanner.visible ? permissionBanner.height + parent.spacing : 0) - inputBox.height - parent.spacing
                clip: true
                model: ChatState.messages
                spacing: Theme.spacing.launcherContentGap / 2

                onCountChanged: positionViewAtEnd()

                // Standard modern-chat layout: user turns right-aligned
                // in an accent bubble, assistant turns left-aligned in a
                // neutral one, both capped at chatBubbleMaxWidth rather
                // than spanning the panel's full width — role is conveyed
                // by side+color, not a "you:"/"goose:" text prefix.
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool isUser: modelData.role === "user"
                    readonly property bool isTool: modelData.role === "tool"
                    readonly property bool isThought: modelData.role === "thought"
                    readonly property bool isMuted: isTool || isThought
                    // Thought bubbles default collapsed -- reasoning traces
                    // are often long and are context for "what is it doing",
                    // not something to read by default. Local to this
                    // delegate instance (not persisted in ChatState) since
                    // it's pure UI-display state, same as every other
                    // ephemeral hover/expand flag in this file.
                    property bool thoughtExpanded: false

                    width: messageList.width
                    height: bubble.height

                    Rectangle {
                        id: bubble
                        width: Math.min(text.implicitWidth + Theme.spacing.launcherRowInset * 2, Theme.spacing.chatBubbleMaxWidth)
                        height: text.implicitHeight + (row.isMuted ? Theme.spacing.launcherRowInset : meta.height + Theme.spacing.launcherRowInset)
                        anchors {
                            right: row.isUser ? parent.right : undefined
                            left: row.isUser ? undefined : parent.left
                        }
                        radius: Theme.radius.input
                        color: row.isMuted ? "transparent" : (row.isUser ? Theme.color.launcherItemSelectedBg : Theme.color.launcherInputBg)

                        Text {
                            id: text
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Theme.spacing.launcherRowInset
                            }
                            text: {
                                if (row.isTool)
                                    return row.modelData.text;
                                if (row.isThought) {
                                    const collapsedPreview = row.modelData.text.length > 60 ? row.modelData.text.slice(0, 60) + "…" : row.modelData.text;
                                    const glyph = row.thoughtExpanded ? "▾" : "▸";
                                    return `${glyph} thinking: ${row.thoughtExpanded ? row.modelData.text : collapsedPreview}`;
                                }
                                return row.modelData.text;
                            }
                            wrapMode: Text.Wrap
                            color: row.isMuted ? Theme.color.launcherPlaceholderFg : Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: row.isMuted ? Theme.font.sizeSmall : Theme.font.sizeBase
                            font.italic: row.isMuted
                            textFormat: row.isMuted ? Text.PlainText : Text.MarkdownText

                            MouseArea {
                                anchors.fill: parent
                                enabled: row.isThought
                                cursorShape: row.isThought ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: row.thoughtExpanded = !row.thoughtExpanded
                            }
                        }

                        Row {
                            id: meta
                            visible: !row.isMuted
                            anchors {
                                left: parent.left
                                top: text.bottom
                                margins: Theme.spacing.launcherRowInset
                            }
                            height: visible ? implicitHeight : 0
                            spacing: Theme.spacing.launcherContentGap

                            Text {
                                text: row.modelData.time ? new Date(row.modelData.time).toLocaleTimeString(Qt.locale(), "hh:mm") : ""
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
                                    onClicked: root.copyToClipboard(row.modelData.text)
                                }
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
                        text: `qubi wants to: ${permissionBanner.visible ? (ChatState.pendingPermission.params?.toolCall?.title ?? "run a tool") : ""}`
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

            Row {
                id: inputBox
                width: parent.width
                height: Theme.spacing.chatComposerHeight
                spacing: Theme.spacing.themePillGap

                Rectangle {
                    id: textFieldBg
                    width: parent.width - sendButton.width - parent.spacing
                    height: parent.height
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
                        text: !GooseAcpSession.sessionReady ? "starting qubi…" : GooseAcpSession.busy ? "qubi is thinking…" : "message qubi…"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    Row {
                        anchors {
                            right: parent.right
                            rightMargin: Theme.spacing.launcherRowInset
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.spacing.launcherContentGap

                        Text {
                            visible: !GooseAcpSession.busy && ChatState.messages.length > 0
                            text: "regenerate"
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.underline: regenArea.containsMouse

                            MouseArea {
                                id: regenArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.regenerate()
                            }
                        }

                        Text {
                            id: stopButton
                            visible: GooseAcpSession.busy
                            text: "stop"
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.underline: stopArea.containsMouse

                            MouseArea {
                                id: stopArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: GooseAcpSession.cancel()
                            }
                        }
                    }

                    TextInput {
                        id: chatInput
                        anchors {
                            fill: parent
                            leftMargin: Theme.spacing.launcherInputTextInset
                            rightMargin: Theme.spacing.launcherInputTextInset + (stopButton.visible || regenArea.containsMouse ? 60 : 0)
                        }
                        clip: true
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        verticalAlignment: TextInput.AlignVCenter

                        Keys.onEscapePressed: ChatState.hide()
                        onAccepted: root.sendFromInput()
                    }
                }

                Rectangle {
                    id: sendButton
                    width: Theme.spacing.chatSendSize
                    height: Theme.spacing.chatSendSize
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: chatInput.text.length > 0 ? Theme.color.accentPurple : Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: chatInput.text.length > 0 ? Theme.color.accentPurple : Theme.color.launcherInputBorder

                    Text {
                        anchors.centerIn: parent
                        text: "↑"
                        color: chatInput.text.length > 0 ? Theme.color.launcherBg : Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.sendFromInput()
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
