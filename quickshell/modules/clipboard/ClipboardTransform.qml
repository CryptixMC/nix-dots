import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Clipboard transform overlay (SUPER+U): wl-paste -> pick a transform ->
// stream an Ollama completion -> wl-copy the result. Direct Ollama HTTP API
// via Process+SplitParser, the same pattern ModelBrowser.qml uses for
// /api/pull -- a goose acp session is unnecessary round-trip overhead for a
// few-second, single-shot, tool-free text transform.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: ClipboardState.visible
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

    readonly property color errorColor: "#f38ba8"

    onVisibleChanged: {
        if (visible) {
            ClipboardState.reset();
            gamingCheckProcess.running = true;
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ClipboardState.hide()
    }

    IpcHandler {
        target: "clipboard"
        function transform(): void {
            ClipboardState.toggle();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ClipboardState.hide()
    }

    // Step 1: never contend with a running game's GPU for even a small
    // model's inference -- same principle Phase 6 (screen context) applies
    // to its own model routing. state.json's "state" field is authoritative
    // (written by ai-workstation-gaming-start/-stop); missing file just
    // means "not gaming" (no ai-workstation session has ever run).
    Process {
        id: gamingCheckProcess
        command: ["cat", "/run/ai-workstation/state.json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let gaming = false;
                let model = "qwen3:4b";
                try {
                    const parsed = JSON.parse(text);
                    gaming = parsed.state === "gaming";
                    if (parsed.model)
                        model = parsed.model;
                } catch (e) {
                    // No state file yet, or malformed -- treat as "not gaming,
                    // use the fast default" rather than blocking the feature.
                }
                if (gaming) {
                    ClipboardState.phase = "gaming-blocked";
                    return;
                }
                root._model = model;
                clipboardTypeProcess.running = true;
            }
        }
    }

    property string _model: "qwen3:4b"

    // Step 2: check MIME types before reading content -- an image-only
    // clipboard has no text/plain entry at all, and trying to read it as
    // text would either return nothing useful or (worse) binary garbage
    // that breaks the later JSON-encoded curl payload.
    Process {
        id: clipboardTypeProcess
        command: ["wl-paste", "--list-types"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const types = text.split("\n").map(t => t.trim()).filter(t => t.length > 0);
                if (types.length === 0) {
                    ClipboardState.phase = "empty";
                    return;
                }
                const hasText = types.some(t => t.startsWith("text/"));
                if (!hasText) {
                    ClipboardState.phase = "image";
                    return;
                }
                clipboardReadProcess.running = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                // wl-paste exits non-zero with no clipboard owner at all
                // (nothing ever copied this session) -- same as "empty".
                if (text.length > 0 && ClipboardState.phase === "checking")
                    ClipboardState.phase = "empty";
            }
        }
    }

    Process {
        id: clipboardReadProcess
        command: ["wl-paste", "--no-newline"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) {
                    ClipboardState.phase = "empty";
                    return;
                }
                if (text.length > ClipboardState.maxChars) {
                    ClipboardState.clipboardText = text;
                    ClipboardState.phase = "oversized";
                    return;
                }
                ClipboardState.clipboardText = text;
                ClipboardState.phase = "picking";
            }
        }
    }

    function runAction(action, instruction) {
        let prompt = action.prompt.replace("{{content}}", ClipboardState.clipboardText);
        if (action.id === "custom")
            prompt = prompt.replace("{{instruction}}", instruction || "Rewrite this");
        ClipboardState.resultText = "";
        ClipboardState.phase = "running";
        ollamaProcess.command = ["curl", "-N", "-s", "-X", "POST", "http://localhost:11434/api/generate",
            "-d", JSON.stringify({ model: root._model, prompt: prompt, stream: true })];
        ollamaProcess.running = true;
    }

    Process {
        id: ollamaProcess
        running: false
        stdout: SplitParser {
            onRead: line => {
                try {
                    const upd = JSON.parse(line);
                    if (upd.error) {
                        ClipboardState.errorMessage = upd.error;
                        ClipboardState.phase = "error";
                        return;
                    }
                    if (upd.response)
                        ClipboardState.resultText += upd.response;
                    if (upd.done) {
                        // wl-copy accepts the text to copy as a positional
                        // argument (falls back to reading stdin only when
                        // given none) -- avoids needing to close stdin
                        // ourselves, which Process has no primitive for
                        // (confirmed against the installed quickshell-io
                        // qmltypes: write()/signal() only, no close/EOF).
                        copyProcess.command = ["wl-copy", "--", ClipboardState.resultText];
                        copyProcess.running = true;
                    }
                } catch (e) {
                    // Non-JSON line (shouldn't happen with /api/generate) -- skip.
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                // curl itself failing (connection refused, etc.) -- Ollama
                // unreachable. Only treat as an error if nothing streamed
                // back yet (a late stderr line after a clean "done" is noise).
                if (text.length > 0 && ClipboardState.phase === "running" && ClipboardState.resultText.length === 0) {
                    ClipboardState.errorMessage = "Could not reach Ollama (localhost:11434) — is it running?";
                    ClipboardState.phase = "error";
                }
            }
        }
    }

    Process {
        id: copyProcess
        running: false
        onExited: ClipboardState.phase = "done"
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
                text: "Clipboard Transform"
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                font.bold: true
            }

            // Informational terminal states
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ClipboardState.phase === "checking"
                text: "reading clipboard…"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ClipboardState.phase === "empty"
                text: "Clipboard is empty — copy something first."
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ClipboardState.phase === "image"
                text: "Clipboard contains an image, not text — nothing to transform."
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ClipboardState.phase === "oversized"
                text: `Clipboard content is too large (${ClipboardState.clipboardText.length} chars, max ${ClipboardState.maxChars}) — copy something shorter.`
                color: root.errorColor
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ClipboardState.phase === "gaming-blocked"
                text: "Clipboard transform is disabled while gaming (keeps the eGPU free for the game)."
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ClipboardState.phase === "error"
                text: ClipboardState.errorMessage
                color: root.errorColor
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            // Action picker
            Column {
                width: parent.width
                spacing: 2
                visible: ClipboardState.phase === "picking"

                Repeater {
                    model: ClipboardState.actions
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: content.width
                        height: Theme.spacing.clipboardRowHeight
                        radius: Theme.radius.input
                        color: rowMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                margins: Theme.spacing.launcherRowInset
                            }
                            spacing: Theme.spacing.launcherIconLabelGap
                            Text {
                                text: row.modelData.glyph
                                color: Theme.color.accentPurple
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                            }
                            Text {
                                text: row.modelData.label
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (row.modelData.id === "custom") {
                                    ClipboardState.phase = "custom-input";
                                    return;
                                }
                                root.runAction(row.modelData, "");
                            }
                        }
                    }
                }
            }

            // Custom prompt entry
            Rectangle {
                width: parent.width
                height: Theme.spacing.launcherInputHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder
                visible: ClipboardState.phase === "custom-input"

                Text {
                    visible: customInput.text.length === 0
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: "What should be done to the clipboard text?"
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                TextInput {
                    id: customInput
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    Keys.onEscapePressed: ClipboardState.hide()
                    onAccepted: root.runAction(ClipboardState.actions.find(a => a.id === "custom"), text)
                }
            }

            // Streaming result
            Column {
                width: parent.width
                spacing: Theme.spacing.launcherContentGap
                visible: ClipboardState.phase === "running" || ClipboardState.phase === "done"

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: ClipboardState.resultText.length > 0 ? ClipboardState.resultText : "thinking…"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }

                Text {
                    width: parent.width
                    visible: ClipboardState.phase === "done"
                    text: "Copied to clipboard ✓ (Escape to close)"
                    color: Theme.color.accentPurple
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }
            }
        }
    }
}
