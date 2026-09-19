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
import "../voice"
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

    // Splits a message into alternating prose / fenced-code segments so
    // code can get its own styling and a copy button. Qt's built-in
    // MarkdownText renders fences as undifferentiated body text, and
    // there is no code-block styling to configure -- hence splitting by
    // hand and rendering the two kinds separately.
    //
    // A fence that never closes is deliberately rendered as prose: a
    // streaming reply is briefly mid-block on almost every turn, and
    // promoting that to a code block would make the bubble flicker
    // between two layouts as the text arrives.
    function splitSegments(src) {
        const lines = (src ?? "").split("\n");
        const segs = [];
        let buf = [];
        let inCode = false;
        let lang = "";
        for (const line of lines) {
            // Regex rather than trimStart(): confirmed live that this
            // QML JS engine has no String.prototype.trimStart, and the
            // resulting TypeError took the whole delegate down.
            if (/^\s*```/.test(line)) {
                if (!inCode) {
                    if (buf.length > 0)
                        segs.push({ code: false, lang: "", text: buf.join("\n") });
                    buf = [];
                    inCode = true;
                    lang = line.trim().slice(3).trim();
                } else {
                    segs.push({ code: true, lang: lang, text: buf.join("\n") });
                    buf = [];
                    inCode = false;
                    lang = "";
                }
                continue;
            }
            buf.push(line);
        }
        if (buf.length > 0) {
            const tail = inCode ? "```" + lang + "\n" + buf.join("\n") : buf.join("\n");
            segs.push({ code: false, lang: "", text: tail });
        }
        return segs.filter(s => s.code || s.text.trim().length > 0);
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
            // Skip past everything this turn just wrote to the db. Those
            // messages are already on screen from the live stream, so
            // without this the next poll would append the whole exchange a
            // second time. Also refreshes the token counters.
            sessionSync.adopt();
            const next = ChatState.dequeue();
            if (next !== undefined)
                root._startTurn(next);
        }

        function onHistoryLoaded() {
            // ACP's replay is unreliable -- some sessions come back with
            // their full history, others with nothing despite having real
            // messages stored. When it replayed nothing, rebuild the
            // conversation from sessions.db instead of resuming to a blank
            // panel. Guarded on the count so a working replay is never
            // duplicated.
            if (GooseAcpSession.historyReplayCount === 0)
                sessionSync.backfill();
            else
                sessionSync.adopt();
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

    // Slash commands, so the things that used to need their own keybind
    // are reachable without leaving the composer.
    readonly property var slashCommands: [
        { name: "/new", help: "start a fresh conversation" },
        { name: "/history", help: "browse past sessions" },
        { name: "/model", help: "switch tier (light/heavy/claude)" },
        { name: "/mode", help: "cycle permission mode" },
        { name: "/mcp", help: "manage MCP extensions" },
        { name: "/voice", help: "voice conversation mode" },
        { name: "/clear", help: "clear this transcript" }
    ]

    // Only offered while the text is still just the command being typed --
    // a message that merely mentions a slash later on isn't a command.
    readonly property var slashMatches: {
        const t = chatInput.text;
        if (!t.startsWith("/") || t.includes("\n") || t.includes(" "))
            return [];
        return root.slashCommands.filter(c => c.name.startsWith(t));
    }

    function runSlash(name) {
        chatInput.text = "";
        switch (name) {
        case "/new":
            ChatState.clear();
            GooseAcpSession.newSession();
            break;
        case "/history":
            SessionsState.toggle();
            break;
        case "/model":
            root.tierPickerOpen = true;
            break;
        case "/mode":
            root.cycleMode();
            break;
        case "/mcp":
            ExtensionsState.toggle();
            break;
        case "/voice":
            VoiceState.visible = !VoiceState.visible;
            break;
        case "/clear":
            ChatState.clear();
            break;
        }
    }

    function sendFromInput() {
        const t = chatInput.text.trim();
        // An exact command runs instead of being sent to the model.
        if (t.startsWith("/") && root.slashCommands.some(c => c.name === t)) {
            root.runSlash(t);
            return;
        }
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
                    readonly property bool isUser: modelData?.role === "user"
                    readonly property bool isTool: modelData?.role === "tool"
                    readonly property bool isThought: modelData?.role === "thought"
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

                    // Muted rows (tool notices, thinking traces) stay a
                    // single plain Text -- they never contain code worth
                    // styling and are collapsed by default anyway.
                    // Defensive on modelData: a delegate can be evaluated
                    // mid-model-reassignment (ChatState swaps the whole
                    // messages array on every append), and an undefined
                    // modelData here threw and blanked the bubble.
                    readonly property var segments: (row.isMuted || !row.modelData) ? [] : root.splitSegments(row.modelData.text)
                    readonly property bool hasCode: (row.segments ?? []).some(s => s.code)

                    Rectangle {
                        id: bubble
                        // A bubble containing code takes the full width --
                        // code lines shouldn't be re-wrapped to hug the
                        // longest prose line.
                        width: row.hasCode ? Theme.spacing.chatBubbleMaxWidth : Math.min(body.implicitWidth + Theme.spacing.launcherRowInset * 2, Theme.spacing.chatBubbleMaxWidth)
                        height: body.implicitHeight + (row.isMuted ? Theme.spacing.launcherRowInset : meta.height + Theme.spacing.launcherRowInset)
                        anchors {
                            right: row.isUser ? parent.right : undefined
                            left: row.isUser ? undefined : parent.left
                        }
                        radius: Theme.radius.input
                        color: row.isMuted ? "transparent" : (row.isUser ? Theme.color.launcherItemSelectedBg : Theme.color.launcherInputBg)

                        Column {
                            id: body
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Theme.spacing.launcherRowInset
                            }
                            spacing: Theme.spacing.launcherContentGap / 2

                            // Muted branch: one plain, collapsible line.
                            Text {
                                visible: row.isMuted
                                width: parent.width
                                text: {
                                    if (!row.isMuted)
                                        return "";
                                    if (row.isTool)
                                        return row.modelData.text;
                                    const collapsedPreview = row.modelData.text.length > 60 ? row.modelData.text.slice(0, 60) + "…" : row.modelData.text;
                                    const glyph = row.thoughtExpanded ? "▾" : "▸";
                                    return `${glyph} thinking: ${row.thoughtExpanded ? row.modelData.text : collapsedPreview}`;
                                }
                                wrapMode: Text.Wrap
                                color: Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                                font.italic: true
                                textFormat: Text.PlainText

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: row.isThought
                                    cursorShape: row.isThought ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: row.thoughtExpanded = !row.thoughtExpanded
                                }
                            }

                            Repeater {
                                model: row.segments

                                delegate: Loader {
                                    required property var modelData
                                    width: body.width
                                    sourceComponent: modelData.code ? codeSegment : proseSegment

                                    Component {
                                        id: proseSegment
                                        Text {
                                            width: body.width
                                            text: modelData.text
                                            wrapMode: Text.Wrap
                                            color: Theme.color.fg
                                            font.family: Theme.font.family
                                            font.pixelSize: Theme.font.sizeBase
                                            textFormat: Text.MarkdownText
                                        }
                                    }

                                    Component {
                                        id: codeSegment
                                        Rectangle {
                                            width: body.width
                                            height: codeText.implicitHeight + codeHeader.height + Theme.spacing.launcherInputTextInset * 2
                                            radius: Theme.radius.input
                                            // The whole shell is already a
                                            // mono font, so a code block
                                            // needs a surface, not a
                                            // typeface change.
                                            color: Theme.color.launcherBg
                                            border.width: Theme.spacing.borderHairline
                                            border.color: Theme.color.launcherBorder

                                            Item {
                                                id: codeHeader
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    top: parent.top
                                                    margins: Theme.spacing.launcherInputTextInset
                                                }
                                                height: Theme.font.sizeSmall + 4

                                                Text {
                                                    anchors.left: parent.left
                                                    text: modelData.lang.length > 0 ? modelData.lang : "code"
                                                    color: Theme.color.launcherPlaceholderFg
                                                    font.family: Theme.font.family
                                                    font.pixelSize: Theme.font.sizeSmall
                                                }

                                                Text {
                                                    anchors.right: parent.right
                                                    text: "copy"
                                                    color: copyCodeArea.containsMouse ? Theme.color.accentPurple : Theme.color.launcherPlaceholderFg
                                                    font.family: Theme.font.family
                                                    font.pixelSize: Theme.font.sizeSmall

                                                    MouseArea {
                                                        id: copyCodeArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: root.copyToClipboard(modelData.text)
                                                    }
                                                }
                                            }

                                            Text {
                                                id: codeText
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    top: codeHeader.bottom
                                                    leftMargin: Theme.spacing.launcherInputTextInset
                                                    rightMargin: Theme.spacing.launcherInputTextInset
                                                }
                                                text: modelData.text
                                                wrapMode: Text.Wrap
                                                color: Theme.color.fg
                                                font.family: Theme.font.family
                                                font.pixelSize: Theme.font.sizeSmall
                                                textFormat: Text.PlainText
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            id: meta
                            visible: !row.isMuted
                            anchors {
                                left: parent.left
                                top: body.bottom
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

            // Slash-command suggestions, floating above the composer.
            Rectangle {
                id: slashPopup
                visible: root.slashMatches.length > 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: turnActions.top
                    bottomMargin: Theme.spacing.launcherContentGap / 2
                }
                height: visible ? slashColumn.implicitHeight + Theme.spacing.launcherContentGap : 0
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                Column {
                    id: slashColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: root.slashMatches

                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: Theme.spacing.launcherRowHeight
                            color: slashRowArea.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacing.launcherRowInset
                                }
                                text: parent.modelData.name
                                color: Theme.color.accentPurple
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }

                            Text {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: Theme.spacing.launcherRowInset
                                }
                                text: parent.modelData.help
                                color: Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }

                            MouseArea {
                                id: slashRowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.runSlash(parent.modelData.name)
                            }
                        }
                    }
                }
            }

            // Turn actions live on their own line above the composer now.
            // They used to float inside the text field, which forced a
            // hardcoded 60px right margin on the input to stop the two
            // overlapping -- and that margin was wrong as soon as the
            // labels changed width.
            Row {
                id: turnActions
                anchors {
                    bottom: inputBox.top
                    right: parent.right
                    bottomMargin: height > 0 ? Theme.spacing.launcherContentGap / 2 : 0
                }
                height: (regenButton.visible || stopButton.visible) ? Theme.font.sizeSmall + 4 : 0
                spacing: Theme.spacing.launcherContentGap

                Text {
                    id: regenButton
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

            // Composer. Grows with the text up to a cap, then pins to the
            // newest line so what you're typing stays visible.
            Item {
                id: inputBox
                anchors {
                    bottom: statusBar.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: Theme.spacing.launcherContentGap
                }
                height: textFieldBg.height

                readonly property int minHeight: Theme.spacing.chatComposerHeight
                readonly property int maxHeight: Theme.spacing.chatComposerMaxHeight

                Rectangle {
                    id: textFieldBg
                    anchors {
                        left: parent.left
                        right: buttonRow.left
                        rightMargin: Theme.spacing.themePillGap
                        bottom: parent.bottom
                    }
                    // Driven only by the text's own content height, never
                    // by anything that depends back on this height -- an
                    // Item's height defaults to its implicitHeight, so a
                    // two-way binding here would be a real loop.
                    height: Math.max(inputBox.minHeight, Math.min(inputBox.maxHeight, chatInput.implicitHeight + Theme.spacing.launcherInputTextInset * 2))
                    radius: Theme.radius.input
                    color: Theme.color.launcherInputBg
                    border.width: Theme.spacing.borderHairline
                    border.color: GooseAcpSession.busy ? Theme.color.accentPurple : Theme.color.launcherInputBorder
                    clip: true

                    Text {
                        visible: chatInput.text.length === 0
                        anchors {
                            left: parent.left
                            leftMargin: Theme.spacing.launcherInputTextInset
                            top: parent.top
                            topMargin: Theme.spacing.launcherInputTextInset
                        }
                        text: !GooseAcpSession.sessionReady ? "starting qubi…" : GooseAcpSession.busy ? "qubi is thinking…" : "message qubi…"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    // TextEdit, not TextInput: multiline with wrapping, the
                    // same plain-QtQuick pattern NotesCapture.qml already
                    // uses (no QtQuick.Controls dependency needed).
                    TextEdit {
                        id: chatInput
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: Theme.spacing.launcherInputTextInset
                            rightMargin: Theme.spacing.launcherInputTextInset
                        }
                        // Scrolls to the newest line once the box has hit
                        // its cap, instead of growing off the top edge.
                        y: Math.min(Theme.spacing.launcherInputTextInset, textFieldBg.height - Theme.spacing.launcherInputTextInset - implicitHeight)
                        height: implicitHeight
                        wrapMode: TextEdit.Wrap
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase

                        Keys.onEscapePressed: ChatState.hide()

                        // Enter sends, Shift+Enter inserts a newline --
                        // TextEdit has no onAccepted, so this is handled
                        // explicitly rather than inherited from TextInput.
                        Keys.onReturnPressed: event => {
                            if (event.modifiers & Qt.ShiftModifier) {
                                chatInput.insert(chatInput.cursorPosition, "\n");
                                event.accepted = true;
                                return;
                            }
                            root.sendFromInput();
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            if (event.modifiers & Qt.ShiftModifier) {
                                chatInput.insert(chatInput.cursorPosition, "\n");
                                event.accepted = true;
                                return;
                            }
                            root.sendFromInput();
                            event.accepted = true;
                        }
                    }
                }

                // Bottom-aligned so the buttons stay put as the field grows.
                Row {
                    id: buttonRow
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        bottomMargin: (inputBox.minHeight - Theme.spacing.chatSendSize) / 2
                    }
                    spacing: Theme.spacing.themePillGap / 2

                    // Hold to talk: records while held, transcribes on
                    // release into the composer for review. Deliberately
                    // does NOT send -- see PushToTalk.qml.
                    Rectangle {
                        id: micButton
                        width: Theme.spacing.chatSendSize
                        height: Theme.spacing.chatSendSize
                        radius: Theme.radius.input
                        color: pushToTalk.recording ? Theme.color.accentPink : (micArea.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent")
                        border.width: Theme.spacing.borderHairline
                        border.color: pushToTalk.recording ? Theme.color.accentPink : Theme.color.launcherInputBorder

                        Text {
                            anchors.centerIn: parent
                            text: "󰍬"
                            renderType: Text.NativeRendering
                            color: pushToTalk.recording ? Theme.color.launcherBg : Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                        }

                        MouseArea {
                            id: micArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onPressed: pushToTalk.start()
                            onReleased: pushToTalk.stop()
                            // A press that ends with the pointer dragged off
                            // the button fires onCanceled, not onReleased --
                            // without this the recorder would keep running
                            // with no visible indication.
                            onCanceled: pushToTalk.stop()
                        }
                    }

                    // Full spoken conversation mode (the old SUPER+O).
                    Rectangle {
                        id: convoButton
                        width: Theme.spacing.chatSendSize
                        height: Theme.spacing.chatSendSize
                        radius: Theme.radius.input
                        color: convoArea.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                        border.width: Theme.spacing.borderHairline
                        border.color: Theme.color.launcherInputBorder

                        Text {
                            anchors.centerIn: parent
                            text: "󰍩"
                            renderType: Text.NativeRendering
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                        }

                        MouseArea {
                            id: convoArea
                            anchors.fill: parent
                            hoverEnabled: true
                            // VoiceState has no toggle() of its own -- the
                            // voice IpcHandler flips `visible` directly,
                            // so do the same rather than inventing an API.
                            onClicked: VoiceState.visible = !VoiceState.visible
                        }
                    }

                    Rectangle {
                        id: sendButton
                        width: Theme.spacing.chatSendSize
                        height: Theme.spacing.chatSendSize
                        radius: Theme.radius.input
                        color: chatInput.text.length > 0 ? Theme.color.accentPurple : Theme.color.launcherInputBg
                        border.width: Theme.spacing.borderHairline
                        border.color: chatInput.text.length > 0 ? Theme.color.accentPurple : Theme.color.launcherInputBorder

                        Text {
                            anchors.centerIn: parent
                            text: "⏎"
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

                // Hold-to-talk recorder. Lives here (not in VoiceOverlay)
                // because its result goes into the composer rather than
                // straight to the model.
                // Picks up turns written to goose's sessions.db by another
                // client (Goose Desktop). Polls only while the panel is
                // open AND no local turn is in flight -- a local turn's
                // messages arrive on the live ACP stream and are also
                // written to the db, so syncing during one would render
                // every message twice.
                SessionSync {
                    id: sessionSync
                    sessionId: GooseAcpSession.sessionId
                    onExternalMessages: entries => ChatState.appendMessages(entries)
                    onTokensUpdated: (total, accumulated) => {
                        ChatState.tokensTotal = total;
                        ChatState.tokensAccumulated = accumulated;
                    }
                }

                PushToTalk {
                    id: pushToTalk
                    onTranscribed: text => {
                        if (text.length === 0)
                            return;
                        // Imperative insert, never a declarative binding on
                        // `text` -- TextEdit assigns text on every keystroke,
                        // which would break such a binding permanently.
                        if (chatInput.text.length > 0 && !chatInput.text.endsWith(" "))
                            chatInput.insert(chatInput.length, " ");
                        chatInput.insert(chatInput.length, text);
                        chatInput.forceActiveFocus();
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
        root._updatePolling();
    }

    // Poll only while the panel is actually open and no local turn is
    // running. Closed: no background subprocess cost at all. Busy: the
    // live ACP stream is already delivering this turn, and the db rows it
    // writes would duplicate it.
    function _updatePolling() {
        sessionSync.setPolling(ChatState.visible && !GooseAcpSession.busy);
    }

    Connections {
        target: ChatState
        function onVisibleChanged() {
            root._updatePolling();
        }
    }

    Connections {
        target: GooseAcpSession
        function onBusyChanged() {
            root._updatePolling();
        }
    }
}
