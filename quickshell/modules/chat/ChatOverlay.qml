import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// Sibling-module singletons reached from the header/status bar. The
// reverse direction already exists (sessions/ and voice/ both import
// "../chat"), and bar/ <-> notifications/ is likewise mutual, so this
// mirrors an established, working pattern in this shell.
import "../sessions"
import "../extensions"
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
    // Tier picker (light/heavy/claude), opened from the bottom-right status
    // item. Replaced the old free-model picker: the engine owns each tier's
    // process now and exposes no per-request model override, so only a
    // whole-tier switch actually does anything (see GooseAcpSession's own
    // switchModel comment and BLOCKERS.md #4).
    property bool tierPickerOpen: false

    function cycleMode() {
        const modes = GooseAcpSession.availableModes;
        if (modes.length === 0)
            return;
        const idx = modes.findIndex(m => m.id === GooseAcpSession.currentModeId);
        const next = modes[(idx + 1) % modes.length];
        GooseAcpSession.setMode(next.id);
    }

    function switchTier(tier) {
        root.tierPickerOpen = false;
        GooseAcpSession.setTier(GooseAcpSession.sessionId, tier, () => {});
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

        function onQubiEscalationOffer(offer) {
            // Real, engine-only notification (Phase 8a) -- the light
            // tier's escalate tool call, surfaced as a user-facing choice
            // instead of the engine ever auto-switching tiers on its own.
            ChatState.pendingEscalation = offer;
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

        // Three anchored bands rather than a Column: header pinned to the
        // top, the composer/banner stack pinned to the bottom, and the
        // message list filling everything between them. See messageList's
        // own comment for why the previous Column + computed-height design
        // was replaced.
        Item {
            id: content
            anchors {
                fill: parent
                margins: Theme.spacing.launcherContentInset
            }

            // An Item with three anchored children rather than a Row with a
            // computed-width spacer -- same reasoning as the panel's own
            // layout above, and it lets the title sit truly centred
            // regardless of how wide the two side buttons are.
            Item {
                id: headerRow
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: Theme.spacing.chatHeaderHeight

                Rectangle {
                    id: historyButton
                    width: Theme.spacing.chatCloseSize
                    height: Theme.spacing.chatCloseSize
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    radius: height / 2
                    color: historyArea.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "☰"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    MouseArea {
                        id: historyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // Reuses the existing full-screen SessionsPicker
                        // rather than reimplementing an in-panel drawer --
                        // it already does list/refresh/resume + history
                        // replay correctly (SessionsPicker.qml).
                        onClicked: SessionsState.toggle()
                    }
                }

                Text {
                    id: titleLabel
                    anchors.centerIn: parent
                    text: "Qubi"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    font.bold: true
                }

                Rectangle {
                    id: closeButton
                    width: Theme.spacing.chatCloseSize
                    height: Theme.spacing.chatCloseSize
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
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

            // Fills whatever vertical space the header and the bottom stack
            // leave over. This used to be a hand-written subtraction naming
            // every sibling, which silently broke TWICE when a new sibling
            // was added without being added to the formula -- first
            // statusPillsRow (cropping the composer off the bottom edge),
            // then escalationBanner. Anchoring to the neighbours' own edges
            // means the geometry tracks itself and that whole class of bug
            // is structurally impossible.
            ListView {
                id: messageList
                anchors {
                    top: headerRow.bottom
                    bottom: permissionBanner.top
                    left: parent.left
                    right: parent.right
                    topMargin: Theme.spacing.launcherContentGap
                    bottomMargin: Theme.spacing.launcherContentGap
                }
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
                anchors {
                    bottom: escalationBanner.top
                    left: parent.left
                    right: parent.right
                    // Collapses to zero gap when hidden, so an inactive
                    // banner costs no vertical space at all (height is
                    // already 0 below; without this the margin would
                    // still push the message list up).
                    bottomMargin: visible ? Theme.spacing.launcherContentGap : 0
                }
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

            // The one new UI element Phase 8a's brief allowed: a minimal
            // inline chip for a real qubi/escalation_offer notification.
            // Same visual pattern as permissionBanner above, deliberately
            // reused rather than invented fresh.
            Rectangle {
                id: escalationBanner
                visible: ChatState.pendingEscalation !== null
                anchors {
                    bottom: inputBox.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: visible ? Theme.spacing.launcherContentGap : 0
                }
                height: visible ? implicitHeight : 0
                implicitHeight: escalationColumn.implicitHeight + Theme.spacing.launcherContentGap
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.accentPurple

                Column {
                    id: escalationColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Theme.spacing.launcherRowInset
                    }
                    spacing: Theme.spacing.launcherContentGap / 2

                    Text {
                        width: parent.width
                        text: escalationBanner.visible ? `qubi wants a bigger model: ${ChatState.pendingEscalation.reason ?? ""}` : ""
                        wrapMode: Text.Wrap
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    Row {
                        spacing: Theme.spacing.launcherContentGap

                        Repeater {
                            // Real option ids from escalate.py/qubi_engine.py's
                            // own qubi/escalation_offer shape — not guessed.
                            model: [
                                { optionId: "escalate_claude", name: "Escalate to Claude" },
                                { optionId: "escalate_heavy_local", name: "Escalate to heavy (local)" },
                                { optionId: "decline", name: "Stay on light" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                width: escalationOptionLabel.implicitWidth + Theme.spacing.themePillPadX * 2
                                height: Theme.spacing.themePillHeight
                                radius: height / 2
                                color: Theme.color.launcherItemSelectedBg
                                border.width: Theme.spacing.borderHairline
                                border.color: Theme.color.launcherInputBorder

                                Text {
                                    id: escalationOptionLabel
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: Theme.color.fg
                                    font.family: Theme.font.family
                                    font.pixelSize: Theme.font.sizeSmall
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        const offer = ChatState.pendingEscalation;
                                        GooseAcpSession.respondToEscalation(offer.session, modelData.optionId);
                                        ChatState.pendingEscalation = null;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                id: inputBox
                anchors {
                    bottom: statusBar.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: Theme.spacing.launcherContentGap
                }
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

            // Status bar: what's loaded and what it's costing, in the same
            // places Claude Code puts them -- tooling on the left, model
            // and usage on the right. Replaces the old round pills that
            // sat above the conversation.
            Item {
                id: statusBar
                anchors {
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                height: Theme.spacing.chatStatusHeight

                Text {
                    id: mcpLabel
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    text: `⚙ ${ExtensionsState.enabledCount} MCP`
                    color: mcpArea.containsMouse ? Theme.color.fg : Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall

                    MouseArea {
                        id: mcpArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: ExtensionsState.toggle()
                    }
                }

                // tier · model · tokens. The tier (not a free model name)
                // is the real unit of choice here -- the engine owns one
                // process per tier and has no per-request model override.
                Text {
                    id: tierLabel
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: {
                        const tier = GooseAcpSession.currentTier;
                        const model = GooseAcpSession.tierModels[tier] ?? "";
                        const tokens = ChatState.tokensTotal;
                        const tokenPart = tokens > 0 ? ` · ${tokens >= 1000 ? (tokens / 1000).toFixed(1) + "k" : tokens}` : "";
                        return `${tier}${model.length > 0 ? " · " + model : ""}${tokenPart}`;
                    }
                    color: tierArea.containsMouse ? Theme.color.fg : Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall

                    MouseArea {
                        id: tierArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.tierPickerOpen = !root.tierPickerOpen
                    }
                }
            }

            // Tier picker, floating above the status bar rather than
            // pushing the conversation around (the old inline picker
            // columns resized the whole panel when opened).
            Rectangle {
                id: tierPicker
                visible: root.tierPickerOpen
                anchors {
                    right: parent.right
                    bottom: statusBar.top
                    bottomMargin: Theme.spacing.launcherContentGap / 2
                }
                width: Theme.spacing.chatTierPickerWidth
                height: tierColumn.implicitHeight + Theme.spacing.launcherContentGap
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                Column {
                    id: tierColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        // Exactly the three tiers qubi/set_tier accepts --
                        // see qubi_engine.py's own tier table. Not derived
                        // from configOptions, which lists models that
                        // cannot actually be switched to.
                        model: ["light", "heavy", "claude"]

                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width
                            height: Theme.spacing.launcherRowHeight
                            color: modelData === GooseAcpSession.currentTier ? Theme.color.launcherItemSelectedBg : "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacing.launcherRowInset
                                    rightMargin: Theme.spacing.launcherRowInset
                                }
                                text: `${parent.modelData} · ${GooseAcpSession.tierModels[parent.modelData] ?? "?"}`
                                elide: Text.ElideRight
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.switchTier(parent.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    onVisibleChanged: {
        if (visible) {
            chatInput.forceActiveFocus();
            // Keeps the MCP count honest without needing the manager
            // overlay to have been opened first.
            ExtensionsState.refresh();
        }
    }
}
