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
import "../modelbrowser"
import "../clipboard"
import "../notes"
import "../core"

// Chat overlay talking to Qubi over a persistent `goose acp` JSON-RPC
// session (GooseAcpSession.qml) — shown/hidden via IPC from a Hyprland
// keybind (same convention as Launcher.qml/ThemeState.qml — see
// hyprland.nix). Backend is GooseAcpSession.qml (see its own header
// comment for what was confirmed live before this was written).
//
// Right-docked sliding panel (not a centered, full-screen-blocking
// overlay like Launcher.qml/SessionsPicker.qml) — the surface itself is
// only QubiTheme.spacing.chatPanelWidth wide, anchored top+bottom+right, so
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
            if (ChatState.visible) {
                root.panelMapped = true;
                // Reopening mid-turn: the flush timer is gated on visibility,
                // so publish whatever accumulated while the panel was hidden
                // instead of showing stale text until the next tick.
                ChatState.flushStreaming();
            } else {
                closeTimer.restart();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: QubiTheme.motion.chatSlide.duration
        onTriggered: root.panelMapped = false
    }

    // Coalesces streamed tokens into a render. ACP chunks arrive far faster
    // than a human reads (and far faster than a markdown re-parse costs), so
    // publishing every one of them just burns frames. ~11Hz is smooth to the
    // eye and bounds the streaming bubble's markdown re-parse to that rate
    // regardless of how fast the model emits. Runs only while a turn is
    // actually in flight, and one final flush happens in commitStreaming()
    // so the last partial chunk is never dropped.
    // Auto-reconnect to the engine. GooseAcpSession has always had a
    // retryConnect() for exactly this, but nothing ever called it: the only
    // caller was meant to be a retry button that was never built. So any
    // `systemctl --user restart qubi-engine` -- routine in this repo, and
    // unavoidable whenever the engine is rebuilt -- left the chat panel
    // permanently dead until the whole shell was restarted, with the only
    // clue a WARN in a log nobody reads. Retrying on a timer turns an
    // engine restart into a few seconds of "reconnecting…" instead.
    Timer {
        id: engineRetryTimer
        interval: 3000
        repeat: true
        running: GooseAcpSession.engineUnavailable
        onTriggered: GooseAcpSession.retryConnect()
    }

    Timer {
        id: streamFlushTimer
        interval: 90
        repeat: true
        running: GooseAcpSession.busy && ChatState.visible
        onTriggered: ChatState.flushStreaming()
    }

    // Same mechanism the Hyprland SUPER+I bind uses -- see the
    // featureMenuItems comment above for why the hamburger menu's Screen
    // Context entry can't just flip ScreenState.visible directly.
    Process {
        id: screenctxTrigger
        running: false
        command: ["quickshell", "ipc", "-p", Quickshell.shellDir, "call", "screenctx", "capture"]
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

    // Hamburger dropdown: every overlay feature this shell has, in one
    // discoverable place, rather than each needing its own memorized
    // keybind. Data-driven (LauncherState.tabs' own convention) so adding
    // a feature later is one more list entry, not a new code path. Actions
    // are plain closures rather than string-dispatched, since every target
    // is a QML singleton already in scope here.
    property bool menuOpen: false

    readonly property var featureMenuItems: [
        { label: "☰  History", action: () => SessionsState.toggle() },
        { label: "⇄  Compare Models", action: () => ChatCompareState.toggle() },
        { label: "🎙  Voice Conversation", action: () => VoiceState.visible = !VoiceState.visible },
        { label: "📋  Clipboard Transform", action: () => ClipboardState.toggle() },
        // ScreenState.visible alone would show an empty overlay -- the real
        // capture flow only starts from ScreenContext.qml's own IpcHandler
        // (it deliberately stays invisible until hyprshot's region-select
        // has already run, see that file's own comment), so this goes
        // through the same external IPC path the Hyprland keybind uses
        // rather than flipping the state singleton directly.
        { label: "🖼  Screen Context", action: () => screenctxTrigger.running = true },
        { label: "📝  Notes Capture", action: () => NotesState.toggle() },
        { label: "🔌  Extensions / MCP", action: () => ExtensionsState.toggle() },
        { label: "📦  Browse Models", action: () => {
                ModelBrowserState.useMode = false;
                ModelBrowserState.visible = true;
            } }
    ]

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
    // A whole fenced block on one line (```lang content```, no newlines)
    // is real, observed model output -- not hypothetical: caught live on
    // the mobile client tonight (a "just answer with the number" turn
    // replied with exactly "```python42```" on one line) and this file
    // has the identical bug, since it's the same algorithm. Fed a
    // self-contained single-line block, the line-based state machine
    // below treats the whole line as an opening fence marker (swallowing
    // everything after the first ``` -- including the closing ``` --
    // into `lang`), never finds a matching close, and the reply silently
    // renders as nothing. Checked and stripped out first, before the
    // multi-line state machine ever sees the line.
    //
    // Two patterns, not one: a single greedy \S* is genuinely ambiguous
    // against "```python42```" -- it happily consumes the whole
    // "python42" as the language name and leaves content empty, since
    // nothing marks where the tag ends and content begins. WITH_LANG
    // requires real whitespace between them (\s+ can't match without an
    // actual space, so it never misfires on the ambiguous case); BARE is
    // the fallback with no separator at all, treating the whole interior
    // as content rather than guessing at a language -- a compact reply
    // renders its real text instead of vanishing into a mislabelled
    // empty block.
    readonly property var _singleLineFenceWithLang: /^\s*```(\S+)\s+([\s\S]*?)```\s*$/
    readonly property var _singleLineFenceBare: /^\s*```([\s\S]*?)```\s*$/

    function _matchSingleLineFence(line) {
        let m = line.match(root._singleLineFenceWithLang);
        if (m)
            return { lang: m[1], text: m[2] };
        m = line.match(root._singleLineFenceBare);
        if (m)
            return { lang: "", text: m[1] };
        return null;
    }

    function splitSegments(src) {
        const lines = (src ?? "").split("\n");
        const segs = [];
        let buf = [];
        let inCode = false;
        let lang = "";
        for (const line of lines) {
            if (!inCode) {
                const single = root._matchSingleLineFence(line);
                if (single) {
                    if (buf.length > 0)
                        segs.push({ code: false, lang: "", text: buf.join("\n") });
                    buf = [];
                    segs.push({ code: true, lang: single.lang, text: single.text });
                    continue;
                }
            }
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
        // Send a prompt from outside the panel (CLI / Hyprland bind):
        //   quickshell ipc -p ~/nix-dots/quickshell call chat send "..."
        // Goes through the same send() path as the composer, so queueing,
        // history and the streaming buffers all behave identically.
        function send(text: string): void {
            root.send(text);
        }
    }

    Connections {
        target: GooseAcpSession

        function onMessageChunk(text) {
            ChatState.pushStreamingText(text);
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
            // The bubble is created empty and filled from the streaming
            // buffer, so creating it costs exactly one model reset per turn
            // instead of one per chunk.
            if (ChatState.streamingThoughtIndex < 0)
                ChatState.streamingThoughtIndex = ChatState.appendMessage("thought", "");
            ChatState.pushStreamingThought(text);
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
            // Fold the streamed buffers into `messages` BEFORE clearing the
            // indices -- commitStreaming writes at those indices.
            ChatState.commitStreaming();
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

    // Shared by the /new slash command and the header's ＋ button so the
    // two can never drift apart.
    function newChat() {
        ChatState.clear();
        GooseAcpSession.newSession();
        root.tierPickerOpen = false;
    }

    function runSlash(name) {
        chatInput.text = "";
        switch (name) {
        case "/new":
            root.newChat();
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
        width: QubiTheme.spacing.chatPanelWidth
        // Deliberately NOT anchors.right: an anchor owns the item's
        // horizontal position and silently overrides any `x` binding, so
        // the slide animation below never rendered a single frame -- while
        // closeTimer above still held this fullscreen, keyboard-grabbing
        // layer surface mapped for the whole chatSlide duration waiting for
        // that animation to finish. All cost, no motion. Positioning with x
        // explicitly gives the Behavior something real to drive.
        x: ChatState.visible ? parent.width - width : parent.width
        color: QubiTheme.color.launcherBg
        border.width: QubiTheme.spacing.borderHairline
        border.color: QubiTheme.color.launcherBorder

        Behavior on x {
            NumberAnimation {
                duration: QubiTheme.motion.chatSlide.duration
                easing.type: QubiTheme.motion.chatSlide.easing
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
                margins: QubiTheme.spacing.launcherContentInset
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
                height: QubiTheme.spacing.chatHeaderHeight

                Rectangle {
                    id: historyButton
                    width: QubiTheme.spacing.chatCloseSize
                    height: QubiTheme.spacing.chatCloseSize
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    radius: height / 2
                    color: historyArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "☰"
                        color: QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase
                    }

                    MouseArea {
                        id: historyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        // Used to jump straight to session history; now
                        // opens the feature menu below instead, which lists
                        // history as its first entry alongside every other
                        // overlay this shell has -- compare, voice, MCP,
                        // clipboard/screen/notes capture, and the model
                        // browser. One discoverable entry point rather than
                        // requiring each to already have a memorized keybind.
                        onClicked: root.menuOpen = !root.menuOpen
                    }
                }

                // Starting a fresh conversation was only reachable by
                // typing /new, which is not discoverable. Same two calls the
                // slash command makes, via the shared newChat() helper.
                Rectangle {
                    id: newChatButton
                    width: QubiTheme.spacing.chatCloseSize
                    height: QubiTheme.spacing.chatCloseSize
                    anchors {
                        left: historyButton.right
                        leftMargin: QubiTheme.spacing.launcherTabGap / 2
                        verticalCenter: parent.verticalCenter
                    }
                    radius: height / 2
                    color: newChatArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "＋"
                        color: newChatArea.containsMouse ? QubiTheme.color.fg : QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase
                    }

                    MouseArea {
                        id: newChatArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.newChat()
                    }
                }

                Text {
                    id: titleLabel
                    anchors.centerIn: parent
                    text: "Qubi"
                    color: QubiTheme.color.fg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeBase
                    font.bold: true
                }

                Rectangle {
                    id: closeButton
                    width: QubiTheme.spacing.chatCloseSize
                    height: QubiTheme.spacing.chatCloseSize
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    radius: height / 2
                    color: closeArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeSmall
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
                    topMargin: QubiTheme.spacing.launcherContentGap
                    bottomMargin: QubiTheme.spacing.launcherContentGap
                }
                clip: true
                model: ChatState.messages
                spacing: QubiTheme.spacing.launcherContentGap / 2

                // Recycle delegate object trees instead of destroying and
                // reallocating them. Each row here is an Item + Rectangle +
                // Column + Repeater + N Loaders + N Texts + MouseAreas, so
                // reuse matters every time the model does change.
                reuseItems: true

                onCountChanged: positionViewAtEnd()

                // Streaming does not change `count` (the bubble already
                // exists and only its text grows), so onCountChanged alone
                // never followed a growing reply -- the view sat still while
                // the answer scrolled off the bottom. contentHeight does
                // change as the bubble reflows, so track that too.
                onContentHeightChanged: {
                    if (ChatState.streamingIndex >= 0 || ChatState.streamingThoughtIndex >= 0)
                        positionViewAtEnd();
                }

                // Standard modern-chat layout: user turns right-aligned
                // in an accent bubble, assistant turns left-aligned in a
                // neutral one, both capped at chatBubbleMaxWidth rather
                // than spanning the panel's full width — role is conveyed
                // by side+color, not a "you:"/"goose:" text prefix.
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
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

                    // reuseItems recycles this object for a different row, so
                    // per-delegate UI state has to be reset explicitly or an
                    // expanded thought "moves" to whatever message lands here
                    // next.
                    ListView.onReused: row.thoughtExpanded = false

                    width: messageList.width
                    height: bubble.height

                    // The text this row actually renders. For the two bubbles
                    // a turn is streaming into, that is the live buffer in
                    // ChatState rather than modelData.text -- which stays
                    // empty until commitStreaming() folds the finished text
                    // back in at end of turn. Everything else reads straight
                    // from the model. This is what keeps a streamed token
                    // from touching the messages array (and therefore from
                    // resetting the whole ListView).
                    readonly property string displayText: {
                        if (!row.modelData)
                            return "";
                        if (row.index === ChatState.streamingIndex && ChatState.streamingText.length > 0)
                            return ChatState.streamingText;
                        if (row.index === ChatState.streamingThoughtIndex && ChatState.streamingThoughtText.length > 0)
                            return ChatState.streamingThoughtText;
                        return row.modelData.text ?? "";
                    }

                    // Muted rows (tool notices, thinking traces) stay a
                    // single plain Text -- they never contain code worth
                    // styling and are collapsed by default anyway.
                    // Defensive on modelData: a delegate can be evaluated
                    // mid-model-reassignment (ChatState swaps the whole
                    // messages array on every append), and an undefined
                    // modelData here threw and blanked the bubble.
                    readonly property var segments: (row.isMuted || !row.modelData) ? [] : root.splitSegments(row.displayText)
                    readonly property bool hasCode: (row.segments ?? []).some(s => s.code)

                    // Independent intrinsic measurement of this row's text,
                    // deliberately NOT a child of `body`.
                    //
                    // bubble.width used to read body.implicitWidth, but a
                    // Column's implicit width is the max of its children's
                    // *assigned* widths, and every child below is assigned
                    // `width: body.width` -> bubble.width - 2*inset. That
                    // makes the width binding self-referential. It converges
                    // rather than oscillating, so Qt never logs a binding
                    // loop -- it just settles on the degenerate fixed point
                    // bubble.width == 2*launcherRowInset == 22px, collapsing
                    // every bubble to a sliver. The hasCode branch hardcodes
                    // chatBubbleMaxWidth and never evaluates
                    // body.implicitWidth, so code-bearing assistant replies
                    // escaped the cycle -- which is exactly why only replies
                    // rendered and user messages (which virtually never carry
                    // a fence) did not.
                    //
                    // A Text with no assigned width and NoWrap reports the
                    // natural width of its longest line and depends on
                    // nothing downstream, restoring the intrinsic measurement
                    // the pre-fdfe753 single-Text layout got for free. Keep
                    // it PlainText: it is a ruler, not a renderer, and
                    // MarkdownText here would re-parse on every chunk.
                    Text {
                        id: intrinsic
                        visible: false
                        text: row.displayText
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase
                        textFormat: Text.PlainText
                        wrapMode: Text.NoWrap
                    }

                    Rectangle {
                        id: bubble
                        // A bubble containing code takes the full width --
                        // code lines shouldn't be re-wrapped to hug the
                        // longest prose line.
                        width: row.hasCode ? QubiTheme.spacing.chatBubbleMaxWidth : Math.min(intrinsic.implicitWidth + QubiTheme.spacing.launcherRowInset * 2, QubiTheme.spacing.chatBubbleMaxWidth)
                        height: body.implicitHeight + (row.isMuted ? QubiTheme.spacing.launcherRowInset : meta.height + QubiTheme.spacing.launcherRowInset)
                        anchors {
                            right: row.isUser ? parent.right : undefined
                            left: row.isUser ? undefined : parent.left
                        }
                        radius: QubiTheme.radius.input
                        color: row.isMuted ? "transparent" : (row.isUser ? QubiTheme.color.launcherItemSelectedBg : QubiTheme.color.launcherInputBg)

                        Column {
                            id: body
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: QubiTheme.spacing.launcherRowInset
                            }
                            spacing: QubiTheme.spacing.launcherContentGap / 2

                            // Muted branch: one plain, collapsible line.
                            Text {
                                visible: row.isMuted
                                width: parent.width
                                // modelData guard for the same reason as
                                // `segments` above: ChatState reassigns the
                                // whole messages array on every streamed
                                // chunk, which resets this ListView's model,
                                // so a delegate can be evaluated with
                                // modelData momentarily undefined. Unguarded,
                                // that threw and blanked the bubble.
                                text: {
                                    if (!row.isMuted || !row.modelData)
                                        return "";
                                    const full = row.displayText;
                                    if (row.isTool)
                                        return full;
                                    const collapsedPreview = full.length > 60 ? full.slice(0, 60) + "…" : full;
                                    const glyph = row.thoughtExpanded ? "▾" : "▸";
                                    return `${glyph} thinking: ${row.thoughtExpanded ? full : collapsedPreview}`;
                                }
                                wrapMode: Text.Wrap
                                color: QubiTheme.color.launcherPlaceholderFg
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
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
                                            color: QubiTheme.color.fg
                                            font.family: QubiTheme.font.family
                                            font.pixelSize: QubiTheme.font.sizeBase
                                            textFormat: Text.MarkdownText
                                        }
                                    }

                                    Component {
                                        id: codeSegment
                                        Rectangle {
                                            width: body.width
                                            height: codeText.implicitHeight + codeHeader.height + QubiTheme.spacing.launcherInputTextInset * 2
                                            radius: QubiTheme.radius.input
                                            // The whole shell is already a
                                            // mono font, so a code block
                                            // needs a surface, not a
                                            // typeface change.
                                            color: QubiTheme.color.launcherBg
                                            border.width: QubiTheme.spacing.borderHairline
                                            border.color: QubiTheme.color.launcherBorder

                                            Item {
                                                id: codeHeader
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    top: parent.top
                                                    margins: QubiTheme.spacing.launcherInputTextInset
                                                }
                                                height: QubiTheme.font.sizeSmall + 4

                                                Text {
                                                    anchors.left: parent.left
                                                    text: modelData.lang.length > 0 ? modelData.lang : "code"
                                                    color: QubiTheme.color.launcherPlaceholderFg
                                                    font.family: QubiTheme.font.family
                                                    font.pixelSize: QubiTheme.font.sizeSmall
                                                }

                                                Text {
                                                    anchors.right: parent.right
                                                    text: "copy"
                                                    color: copyCodeArea.containsMouse ? QubiTheme.color.accentPurple : QubiTheme.color.launcherPlaceholderFg
                                                    font.family: QubiTheme.font.family
                                                    font.pixelSize: QubiTheme.font.sizeSmall

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
                                                    leftMargin: QubiTheme.spacing.launcherInputTextInset
                                                    rightMargin: QubiTheme.spacing.launcherInputTextInset
                                                }
                                                text: modelData.text
                                                wrapMode: Text.Wrap
                                                color: QubiTheme.color.fg
                                                font.family: QubiTheme.font.family
                                                font.pixelSize: QubiTheme.font.sizeSmall
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
                                margins: QubiTheme.spacing.launcherRowInset
                            }
                            height: visible ? implicitHeight : 0
                            spacing: QubiTheme.spacing.launcherContentGap

                            Text {
                                text: row.modelData?.time ? new Date(row.modelData.time).toLocaleTimeString(Qt.locale(), "hh:mm") : ""
                                color: QubiTheme.color.launcherPlaceholderFg
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
                            }

                            Text {
                                text: "copy"
                                color: QubiTheme.color.launcherPlaceholderFg
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
                                font.underline: copyArea.containsMouse

                                MouseArea {
                                    id: copyArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.copyToClipboard(row.displayText)
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
                    bottomMargin: visible ? QubiTheme.spacing.launcherContentGap : 0
                }
                height: visible ? implicitHeight : 0
                implicitHeight: permissionColumn.implicitHeight + QubiTheme.spacing.launcherContentGap
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.accentPurple

                Column {
                    id: permissionColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: QubiTheme.spacing.launcherRowInset
                    }
                    spacing: QubiTheme.spacing.launcherContentGap / 2

                    Text {
                        width: parent.width
                        text: `qubi wants to: ${permissionBanner.visible ? (ChatState.pendingPermission.params?.toolCall?.title ?? "run a tool") : ""}`
                        wrapMode: Text.Wrap
                        color: QubiTheme.color.fg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase
                    }

                    Row {
                        spacing: QubiTheme.spacing.launcherContentGap

                        Repeater {
                            model: permissionBanner.visible ? (ChatState.pendingPermission.params?.options ?? []) : []

                            delegate: Rectangle {
                                required property var modelData
                                width: optionLabel.implicitWidth + QubiTheme.spacing.themePillPadX * 2
                                height: QubiTheme.spacing.themePillHeight
                                radius: height / 2
                                color: QubiTheme.color.launcherItemSelectedBg
                                border.width: QubiTheme.spacing.borderHairline
                                border.color: QubiTheme.color.launcherInputBorder

                                Text {
                                    id: optionLabel
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: QubiTheme.color.fg
                                    font.family: QubiTheme.font.family
                                    font.pixelSize: QubiTheme.font.sizeSmall
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
                    bottom: activityStrip.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: visible ? QubiTheme.spacing.launcherContentGap : 0
                }
                height: visible ? implicitHeight : 0
                implicitHeight: escalationColumn.implicitHeight + QubiTheme.spacing.launcherContentGap
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.accentPurple

                Column {
                    id: escalationColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: QubiTheme.spacing.launcherRowInset
                    }
                    spacing: QubiTheme.spacing.launcherContentGap / 2

                    Text {
                        width: parent.width
                        text: escalationBanner.visible ? `qubi wants a bigger model: ${ChatState.pendingEscalation.reason ?? ""}` : ""
                        wrapMode: Text.Wrap
                        color: QubiTheme.color.fg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase
                    }

                    Row {
                        spacing: QubiTheme.spacing.launcherContentGap

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
                                width: escalationOptionLabel.implicitWidth + QubiTheme.spacing.themePillPadX * 2
                                height: QubiTheme.spacing.themePillHeight
                                radius: height / 2
                                color: QubiTheme.color.launcherItemSelectedBg
                                border.width: QubiTheme.spacing.borderHairline
                                border.color: QubiTheme.color.launcherInputBorder

                                Text {
                                    id: escalationOptionLabel
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: QubiTheme.color.fg
                                    font.family: QubiTheme.font.family
                                    font.pixelSize: QubiTheme.font.sizeSmall
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
                    bottomMargin: QubiTheme.spacing.launcherContentGap / 2
                }
                height: visible ? slashColumn.implicitHeight + QubiTheme.spacing.launcherContentGap : 0
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.launcherInputBorder

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
                            height: QubiTheme.spacing.launcherRowHeight
                            color: slashRowArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: QubiTheme.spacing.launcherRowInset
                                }
                                text: parent.modelData.name
                                color: QubiTheme.color.accentPurple
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
                            }

                            Text {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: QubiTheme.spacing.launcherRowInset
                                }
                                text: parent.modelData.help
                                color: QubiTheme.color.launcherPlaceholderFg
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
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
                    bottomMargin: height > 0 ? QubiTheme.spacing.launcherContentGap / 2 : 0
                }
                height: (regenButton.visible || stopButton.visible) ? QubiTheme.font.sizeSmall + 4 : 0
                spacing: QubiTheme.spacing.launcherContentGap

                Text {
                    id: regenButton
                    visible: !GooseAcpSession.busy && ChatState.messages.length > 0
                    text: "regenerate"
                    color: QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeSmall
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
                    color: QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeSmall
                    font.underline: stopArea.containsMouse

                    MouseArea {
                        id: stopArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: GooseAcpSession.cancel()
                    }
                }
            }

            // Activity indicator. The panel used to communicate exactly one
            // bit -- the composer placeholder said "qubi is thinking…" for
            // the entire turn -- which on a local reasoning model means a
            // motionless panel for a very long time: measured 48s of silence
            // before the first token on a one-sentence question, and 60s
            // total for "what is 6 times 7". This names the actual step and,
            // while reasoning, shows a rolling fragment of what the model is
            // working through, so a slow turn reads as busy rather than
            // frozen.
            Rectangle {
                id: activityStrip
                visible: GooseAcpSession.engineUnavailable || GooseAcpSession.busy || GooseAcpSession.phase === "starting_model" || GooseAcpSession.phase === "switching_tier" || GooseAcpSession.phase === "reloading_hardware"
                anchors {
                    bottom: inputBox.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: visible ? QubiTheme.spacing.launcherContentGap : 0
                }
                height: visible ? implicitHeight : 0
                implicitHeight: activityColumn.implicitHeight + QubiTheme.spacing.launcherContentGap
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.accentPurple

                readonly property string label: {
                    if (GooseAcpSession.engineUnavailable)
                        return "engine offline — reconnecting…";
                    switch (GooseAcpSession.phase) {
                    case "starting_model":
                        return "starting model";
                    case "switching_tier":
                        return "switching tier";
                    case "reloading_hardware":
                        return "hardware changed, reloading";
                    case "queued":
                        return "queued";
                    case "reasoning":
                        return "thinking";
                    case "responding":
                        return "writing reply";
                    case "tool":
                        return "running tool";
                    default:
                        return "working";
                    }
                }

                Column {
                    id: activityColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: QubiTheme.spacing.launcherRowInset
                    }
                    spacing: QubiTheme.spacing.sessionMetaGap

                    Row {
                        spacing: QubiTheme.spacing.launcherIconLabelGap

                        // Pure-QML spinner: no image asset, no layer, and it
                        // stops dead when the strip is hidden so an idle
                        // panel runs no animation at all.
                        Rectangle {
                            id: spinnerDot
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: QubiTheme.color.accentPurple

                            SequentialAnimation on opacity {
                                running: activityStrip.visible
                                loops: Animation.Infinite
                                NumberAnimation {
                                    to: 0.25
                                    duration: 520
                                    easing.type: Easing.InOutQuad
                                }
                                NumberAnimation {
                                    to: 1
                                    duration: 520
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: GooseAcpSession.engineUnavailable ? activityStrip.label : `${activityStrip.label} · ${GooseAcpSession.currentTier}`
                            color: QubiTheme.color.fg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeSmall
                        }
                    }

                    // The rolling "what is it thinking about" line. Empty for
                    // every phase that has no detail, and collapsed to zero
                    // height so the strip stays one line tall then.
                    Text {
                        visible: GooseAcpSession.phaseDetail.length > 0
                        height: visible ? implicitHeight : 0
                        width: parent.width
                        text: GooseAcpSession.phaseDetail
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        color: QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeSmall
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
                    bottomMargin: QubiTheme.spacing.launcherContentGap
                }
                height: textFieldBg.height

                readonly property int minHeight: QubiTheme.spacing.chatComposerHeight
                readonly property int maxHeight: QubiTheme.spacing.chatComposerMaxHeight

                Rectangle {
                    id: textFieldBg
                    anchors {
                        left: parent.left
                        right: buttonRow.left
                        rightMargin: QubiTheme.spacing.themePillGap
                        bottom: parent.bottom
                    }
                    // Driven only by the text's own content height, never
                    // by anything that depends back on this height -- an
                    // Item's height defaults to its implicitHeight, so a
                    // two-way binding here would be a real loop.
                    height: Math.max(inputBox.minHeight, Math.min(inputBox.maxHeight, chatInput.implicitHeight + QubiTheme.spacing.launcherInputTextInset * 2))
                    radius: QubiTheme.radius.input
                    color: QubiTheme.color.launcherInputBg
                    border.width: QubiTheme.spacing.borderHairline
                    border.color: GooseAcpSession.busy ? QubiTheme.color.accentPurple : QubiTheme.color.launcherInputBorder
                    clip: true

                    Text {
                        visible: chatInput.text.length === 0
                        anchors {
                            left: parent.left
                            leftMargin: QubiTheme.spacing.launcherInputTextInset
                            top: parent.top
                            topMargin: QubiTheme.spacing.launcherInputTextInset
                        }
                        text: !GooseAcpSession.sessionReady ? "starting qubi…" : GooseAcpSession.busy ? "qubi is thinking…" : "message qubi…"
                        color: QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase
                    }

                    // TextEdit, not TextInput: multiline with wrapping, the
                    // same plain-QtQuick pattern NotesCapture.qml already
                    // uses (no QtQuick.Controls dependency needed).
                    TextEdit {
                        id: chatInput
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: QubiTheme.spacing.launcherInputTextInset
                            rightMargin: QubiTheme.spacing.launcherInputTextInset
                        }
                        // Scrolls to the newest line once the box has hit
                        // its cap, instead of growing off the top edge.
                        y: Math.min(QubiTheme.spacing.launcherInputTextInset, textFieldBg.height - QubiTheme.spacing.launcherInputTextInset - implicitHeight)
                        height: implicitHeight
                        wrapMode: TextEdit.Wrap
                        color: QubiTheme.color.fg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeBase

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
                        bottomMargin: (inputBox.minHeight - QubiTheme.spacing.chatSendSize) / 2
                    }
                    spacing: QubiTheme.spacing.themePillGap / 2

                    // Hold to talk: records while held, transcribes on
                    // release into the composer for review. Deliberately
                    // does NOT send -- see PushToTalk.qml.
                    Rectangle {
                        id: micButton
                        width: QubiTheme.spacing.chatSendSize
                        height: QubiTheme.spacing.chatSendSize
                        radius: QubiTheme.radius.input
                        color: pushToTalk.recording ? QubiTheme.color.accentPink : (micArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent")
                        border.width: QubiTheme.spacing.borderHairline
                        border.color: pushToTalk.recording ? QubiTheme.color.accentPink : QubiTheme.color.launcherInputBorder

                        Text {
                            anchors.centerIn: parent
                            text: "󰍬"
                            renderType: Text.NativeRendering
                            color: pushToTalk.recording ? QubiTheme.color.launcherBg : QubiTheme.color.launcherPlaceholderFg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeBase
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
                        width: QubiTheme.spacing.chatSendSize
                        height: QubiTheme.spacing.chatSendSize
                        radius: QubiTheme.radius.input
                        color: convoArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"
                        border.width: QubiTheme.spacing.borderHairline
                        border.color: QubiTheme.color.launcherInputBorder

                        Text {
                            anchors.centerIn: parent
                            text: "󰍩"
                            renderType: Text.NativeRendering
                            color: QubiTheme.color.launcherPlaceholderFg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeBase
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
                        width: QubiTheme.spacing.chatSendSize
                        height: QubiTheme.spacing.chatSendSize
                        radius: QubiTheme.radius.input
                        color: chatInput.text.length > 0 ? QubiTheme.color.accentPurple : QubiTheme.color.launcherInputBg
                        border.width: QubiTheme.spacing.borderHairline
                        border.color: chatInput.text.length > 0 ? QubiTheme.color.accentPurple : QubiTheme.color.launcherInputBorder

                        Text {
                            anchors.centerIn: parent
                            text: "⏎"
                            color: chatInput.text.length > 0 ? QubiTheme.color.launcherBg : QubiTheme.color.launcherPlaceholderFg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeBase
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
                height: QubiTheme.spacing.chatStatusHeight

                Text {
                    id: mcpLabel
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    text: `⚙ ${ExtensionsState.enabledCount} MCP`
                    color: mcpArea.containsMouse ? QubiTheme.color.fg : QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeSmall

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
                        // An ad hoc qubi/use_model pick reports as
                        // "model:<tag>" (see ModelBrowser.qml's
                        // currentModelName for the full rationale) -- render
                        // it as just the model name rather than that literal
                        // string, since there's no separate tier label worth
                        // showing for a one-off pick.
                        const isAdhoc = tier.startsWith("model:");
                        const label = isAdhoc ? tier.slice("model:".length) : tier;
                        const model = isAdhoc ? "" : (GooseAcpSession.tierModels[tier] ?? "");
                        const tokens = ChatState.tokensTotal;
                        const tokenPart = tokens > 0 ? ` · ${tokens >= 1000 ? (tokens / 1000).toFixed(1) + "k" : tokens}` : "";
                        return `${label}${model.length > 0 ? " · " + model : ""}${tokenPart}`;
                    }
                    color: tierArea.containsMouse ? QubiTheme.color.fg : QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeSmall

                    MouseArea {
                        id: tierArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.tierPickerOpen = !root.tierPickerOpen
                    }
                }
            }

            // Tier picker, floating above the status bar rather than
            // Feature menu, floating below the hamburger button rather than
            // replacing the header (same "float above the layout, don't
            // resize the panel" choice tierPicker below makes).
            Rectangle {
                id: featureMenu
                visible: root.menuOpen
                anchors {
                    top: headerRow.bottom
                    left: parent.left
                    topMargin: QubiTheme.spacing.launcherContentGap / 2
                }
                width: QubiTheme.spacing.chatTierPickerWidth
                height: featureMenuColumn.implicitHeight + QubiTheme.spacing.launcherContentGap
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.launcherInputBorder
                // Floats over the message list, which is not itself a
                // MouseArea-blocking layer -- without an explicit stacking
                // order the menu could render behind later-declared
                // siblings (the tier picker, the composer).
                z: 10

                Column {
                    id: featureMenuColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: root.featureMenuItems

                        delegate: Rectangle {
                            id: menuRow
                            required property var modelData
                            width: parent.width
                            height: QubiTheme.spacing.launcherRowHeight
                            color: menuArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: QubiTheme.spacing.launcherRowInset
                                    rightMargin: QubiTheme.spacing.launcherRowInset
                                }
                                text: menuRow.modelData.label
                                elide: Text.ElideRight
                                color: QubiTheme.color.fg
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
                            }

                            MouseArea {
                                id: menuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    menuRow.modelData.action();
                                    root.menuOpen = false;
                                }
                            }
                        }
                    }
                }
            }

            // pushing the conversation around (the old inline picker
            // columns resized the whole panel when opened).
            Rectangle {
                id: tierPicker
                visible: root.tierPickerOpen
                anchors {
                    right: parent.right
                    bottom: statusBar.top
                    bottomMargin: QubiTheme.spacing.launcherContentGap / 2
                }
                width: QubiTheme.spacing.chatTierPickerWidth
                height: tierColumn.implicitHeight + QubiTheme.spacing.launcherContentGap
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: QubiTheme.spacing.borderHairline
                border.color: QubiTheme.color.launcherInputBorder

                Column {
                    id: tierColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        // Derived from the engine's live tier table
                        // (qubi/status -> GooseAcpSession.tierModels) rather
                        // than a hardcoded list, because tiers are now
                        // config-driven: `fast` appeared by adding it to
                        // config.json, and a hardcoded list would have
                        // silently hidden it. Ordered cheapest-first, with
                        // any tier not in the preference list appended so an
                        // unknown one is never dropped.
                        model: {
                            const order = ["fast", "light", "heavy", "claude"];
                            const names = Object.keys(GooseAcpSession.tierModels ?? ({}));
                            const known = order.filter(t => names.includes(t));
                            return known.concat(names.filter(t => !order.includes(t)));
                        }

                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width
                            height: QubiTheme.spacing.launcherRowHeight
                            color: modelData === GooseAcpSession.currentTier ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: QubiTheme.spacing.launcherRowInset
                                    rightMargin: QubiTheme.spacing.launcherRowInset
                                }
                                text: `${parent.modelData} · ${GooseAcpSession.tierModels[parent.modelData] ?? "?"}`
                                elide: Text.ElideRight
                                color: QubiTheme.color.fg
                                font.family: QubiTheme.font.family
                                font.pixelSize: QubiTheme.font.sizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.switchTier(parent.modelData)
                            }
                        }
                    }

                    // Separator + escape hatch into the full model browser.
                    // The tier list above only offers the models the tiers
                    // are currently pointed at; this is how you change what
                    // a tier points AT, or install something new.
                    Rectangle {
                        width: parent.width
                        height: QubiTheme.spacing.borderHairline
                        color: QubiTheme.color.launcherBorder
                    }

                    Rectangle {
                        id: moreModelsRow
                        width: parent.width
                        height: QubiTheme.spacing.launcherRowHeight
                        color: moreModelsArea.containsMouse ? QubiTheme.color.launcherItemSelectedBg : "transparent"

                        Text {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: QubiTheme.spacing.launcherRowInset
                                rightMargin: QubiTheme.spacing.launcherRowInset
                            }
                            text: "⊕  more models…"
                            elide: Text.ElideRight
                            color: QubiTheme.color.accentPurple
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeSmall
                        }

                        MouseArea {
                            id: moreModelsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                // useMode, not a tier assignment -- picking
                                // a model here switches THIS conversation to
                                // it directly (qubi/use_model), it does not
                                // change what "light"/"fast"/etc. mean for
                                // anyone else. See ModelBrowserState.useMode.
                                ModelBrowserState.useMode = true;
                                root.tierPickerOpen = false;
                                ModelBrowserState.visible = true;
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
