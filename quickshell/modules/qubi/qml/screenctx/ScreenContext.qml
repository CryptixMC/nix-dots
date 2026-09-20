import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// SUPER+I: region-select screen capture -> vision description or OCR text,
// routed by ai-workstation state (never loads a VLM onto a GPU a game
// might be using -- see egpu-dock-undock/game-log-discovery skills):
//   gaming    -> tesseract OCR (CPU only), result copied to clipboard +
//                notified, overlay never shown at all (never steals focus
//                from a fullscreen game).
//   docked    -> qwen3-vl:4b via direct Ollama /api/generate (images[]
//                field, Ollama's own API shape -- not the ACP image
//                content-block format, since this bypasses goose acp
//                entirely, same as ClipboardTransform.qml's precedent).
//   undocked  -> tesseract OCR, shown in the normal overlay.
//
// Confirmed live this session (see BLOCKERS.md/PROGRESS.md): the pinned
// Goose 1.47.0 genuinely advertises promptCapabilities.image=true and
// correctly processes a real base64 image content block via
// session/prompt (tested through the claude-code provider, which doesn't
// depend on the blocked local GPU) -- so the image pipeline itself is
// real, not a guess. Local qwen3-vl:4b routing specifically (the Ollama
// /api/generate path below) could NOT be live-tested tonight -- blocked
// by the dead-KFD state like everything else needing the local GPU.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: ScreenState.visible
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

    readonly property string capturePath: "/tmp/qubi-screenctx-capture.png"
    readonly property color errorColor: "#f38ba8"

    IpcHandler {
        target: "screenctx"
        function capture(): void {
            ScreenState.reset();
            gamingCheckProcess.running = true;
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ScreenState.hide()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ScreenState.hide()
    }

    Process {
        id: gamingCheckProcess
        command: ["cat", "/run/ai-workstation/state.json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let state = "undocked";
                try {
                    state = JSON.parse(text).state ?? "undocked";
                } catch (e) {
                    // No state file yet -- treat as undocked (OCR), the
                    // safe/cheap default.
                }
                root._route = state === "gaming" ? "ocr-gaming" : state === "docked" ? "vision" : "ocr";
                ScreenState.route = root._route;
                // Deliberately NOT setting ScreenState.visible here --
                // this window must stay fully invisible while hyprshot's
                // own slurp region-select is active, or its centered box
                // sits on screen in the way of the selection (confirmed
                // live: a real, reported bug). Only becomes visible once
                // there's an actual result to show (checkCaptureProcess,
                // once past the capture step).
                captureProcess.running = true;
            }
        }
    }

    property string _route: "ocr"

    Process {
        id: captureProcess
        command: ["bash", "-c", `rm -f ${root.capturePath}; hyprshot -m region --raw > ${root.capturePath} 2>/dev/null`]
        running: false
        onExited: (exitCode, exitStatus) => {
            checkCaptureProcess.running = true;
        }
    }

    // hyprshot writes nothing (empty file) if the user cancels the region
    // select (Escape during slurp) -- check size before treating this as
    // a real capture.
    Process {
        id: checkCaptureProcess
        command: ["bash", "-c", `stat -c%s ${root.capturePath} 2>/dev/null || echo 0`]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const size = parseInt(text.trim(), 10) || 0;
                if (size < 100) {
                    // Cancelled or failed capture -- reset silently, same
                    // as any other cancel-with-no-error path in this repo.
                    ScreenState.hide();
                    return;
                }
                ScreenState.phase = "processing";
                // Only becomes visible now -- past the actual screen
                // capture, showing "processing"/"result"/"error", never
                // during the capture itself (see the comment above on why).
                // Gaming stays fully silent throughout, still -- no
                // overlay at all, only a clipboard-copy + notification at
                // the end, never stealing focus from a fullscreen game.
                if (root._route !== "ocr-gaming")
                    ScreenState.visible = true;
                if (root._route === "vision")
                    b64Process.running = true;
                else
                    ocrProcess.running = true;
            }
        }
    }

    Process {
        id: ocrProcess
        command: ["tesseract", root.capturePath, "-"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const extracted = text.trim();
                if (root._route === "ocr-gaming") {
                    copyProcess.command = ["wl-copy", "--", extracted];
                    copyProcess.running = true;
                    notifyProcess.command = ["hyprctl", "notify", "-1", "4000", "rgb(89dceb)",
                        extracted.length > 0 ? "Screen text copied to clipboard" : "No text found on screen"];
                    notifyProcess.running = true;
                    return;
                }
                ScreenState.resultText = extracted.length > 0 ? extracted : "(no text found in the selected region)";
                ScreenState.phase = "result";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && ScreenState.phase === "processing") {
                    ScreenState.errorMessage = "OCR failed — is tesseract installed?";
                    ScreenState.phase = "error";
                }
            }
        }
    }

    Process {
        id: visionProcess
        running: false
        stdout: SplitParser {
            onRead: line => {
                try {
                    const upd = JSON.parse(line);
                    if (upd.error) {
                        ScreenState.errorMessage = upd.error;
                        ScreenState.phase = "error";
                        return;
                    }
                    if (upd.response)
                        ScreenState.resultText += upd.response;
                    if (upd.done)
                        ScreenState.phase = "result";
                } catch (e) {
                    // Skip non-JSON lines.
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && ScreenState.phase === "processing" && ScreenState.resultText.length === 0) {
                    ScreenState.errorMessage = "Could not reach Ollama (localhost:11434) for qwen3-vl:4b — is it running?";
                    ScreenState.phase = "error";
                }
            }
        }
    }

    Process {
        id: b64Process
        command: ["base64", "-w0", root.capturePath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const b64 = text.trim();
                visionProcess.command = ["curl", "-N", "-s", "-X", "POST", "http://localhost:11434/api/generate",
                    "-d", JSON.stringify({
                        model: "qwen3-vl:4b",
                        prompt: "Describe what's on screen in this screenshot, concisely.",
                        images: [b64],
                        stream: true
                    })];
                visionProcess.running = true;
            }
        }
    }

    Process {
        id: copyProcess
        running: false
    }
    Process {
        id: notifyProcess
        running: false
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Theme.spacing.screenctxPanelWidth + 200
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
                text: "Screen Context"
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                font.bold: true
            }

            Text {
                width: parent.width
                visible: ScreenState.phase === "processing"
                text: ScreenState.route === "vision" ? "asking qwen3-vl…" : "reading text…"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ScreenState.phase === "error"
                text: ScreenState.errorMessage
                color: root.errorColor
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: ScreenState.phase === "result"
                text: ScreenState.resultText
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }
    }
}
