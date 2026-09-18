pragma Singleton
import QtQuick

// Show/hide state + message history for the chat overlay, reachable from
// ChatOverlay.qml's IpcHandler (external `quickshell ipc call` from a
// Hyprland keybind, same convention as launcher/theme) and from the window
// itself. History lives here (not on the window) so it survives a
// hide/show cycle instead of resetting like Launcher's search text does.
//
// Backend is GooseAcpSession.qml (a persistent `goose acp` JSON-RPC
// session) — this singleton owns UI-facing chat state only. `busy` lives
// on GooseAcpSession itself now (it reflects a real in-flight ACP turn,
// not a spawned-process lifetime), not duplicated here.
QtObject {
    id: root

    property bool visible: false
    property var messages: []

    // The raw session/request_permission JSON-RPC request currently
    // awaiting a real user decision (null when nothing's pending). Only
    // ever set outside "auto" mode — auto mode never sends permission
    // requests at all (confirmed live).
    property var pendingPermission: null

    // Index into `messages` of the assistant bubble currently being
    // streamed into, or -1 if no turn is in flight. Tracked explicitly
    // (not "whichever message is last") because a queued user message can
    // legitimately be appended after the streaming placeholder — see
    // pendingQueue below and ChatOverlay.qml's _startTurn().
    property int streamingIndex: -1

    // Same pattern as streamingIndex, but for "thought" bubbles: ACP
    // delivers reasoning content as many small chunks, and without this
    // each chunk was landing as its own brand-new bubble via appendMessage
    // (confirmed live: thinking text rendered one word per line). Reset
    // alongside streamingIndex in onTurnComplete.
    property int streamingThoughtIndex: -1

    // Messages sent while a turn is already in flight queue here instead
    // of being dropped or blocked — drained one at a time as each prior
    // turn's turnComplete fires (see ChatOverlay.qml).
    property var pendingQueue: []

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }

    // Returns the new message's index, so callers can track a specific
    // bubble (e.g. as the streaming target) regardless of what's appended
    // after it later.
    function appendMessage(role, text) {
        messages = messages.concat([{
            role: role,
            text: text,
            time: Date.now()
        }]);
        return messages.length - 1;
    }

    // Mutates messages[streamingIndex] in place (for streaming assistant
    // text) by reassigning the whole array — required for QML change
    // notification, same discipline as UsageStore.qml/ThemeState.qml's own
    // array/object reassignment pattern.
    function appendToStreamingMessage(text, index) {
        const idx = index ?? root.streamingIndex;
        if (idx < 0 || idx >= root.messages.length)
            return;
        const copy = root.messages.slice();
        const target = Object.assign({}, copy[idx]);
        target.text = (target.text ?? "") + text;
        copy[idx] = target;
        root.messages = copy;
    }

    function enqueue(text) {
        root.pendingQueue = root.pendingQueue.concat([text]);
    }

    function dequeue() {
        if (root.pendingQueue.length === 0)
            return undefined;
        const next = root.pendingQueue[0];
        root.pendingQueue = root.pendingQueue.slice(1);
        return next;
    }

    function clear() {
        messages = [];
        pendingQueue = [];
        streamingIndex = -1;
        pendingPermission = null;
    }
}
