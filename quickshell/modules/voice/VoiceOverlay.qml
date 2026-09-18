import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../../theme"
import "../chat"

// SUPER+O: full-screen voice conversation overlay. Push-to-talk only (hold
// Space to record, release to send) -- no barge-in, no continuous
// listening, matching the plan's own caution to verify the simpler shape
// first. Canvas-based reactive blob, not a ShaderEffect/qsb shader --
// the shader path (reusing modules/wallpaper/'s qsb build approach) could
// not be validated in staging tonight given time, so this ships the
// Canvas fallback the plan itself allows for exactly this situation,
// rather than a shader "behind a flag" that was never actually proven to
// compile. Reuses the main GooseAcpSession singleton (see VoiceState.qml's
// header comment for why, vs. ChatCompare's genuinely-independent panes).
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: VoiceState.visible
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

    readonly property string wavPath: "/tmp/qubi-voice-capture.wav"
    readonly property var micSource: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: root.micSource ? [root.micSource] : []
    }

    PwNodePeakMonitor {
        id: peakMonitor
        node: root.micSource
        enabled: VoiceState.phase === "recording"
        onPeakChanged: VoiceState.micPeak = peakMonitor.peak
    }

    onVisibleChanged: {
        if (visible) {
            VoiceState.reset();
            readyCheckProcess.running = true;
        } else if (recordProcess.running) {
            recordProcess.running = false;
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: VoiceState.hide()
    }

    IpcHandler {
        target: "voice"
        function toggle(): void {
            VoiceState.visible = !VoiceState.visible;
        }
    }

    Process {
        id: readyCheckProcess
        command: ["voice-models-ready"]
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                VoiceState.errorMessage = "Voice models not downloaded yet — the first push-to-talk will trigger the download (whisper ~140MB, piper voice smaller); this may take a moment.";
        }
    }

    Item {
        id: keyCapture
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space && !event.isAutoRepeat && VoiceState.phase === "idle") {
                root.startRecording();
                event.accepted = true;
            }
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Space && !event.isAutoRepeat && VoiceState.phase === "recording") {
                root.stopRecordingAndSend();
                event.accepted = true;
            }
        }
    }

    function startRecording() {
        VoiceState.phase = "recording";
        VoiceState.markStage("record");
        recordProcess.command = ["pw-record", "--rate", "16000", "--channels", "1", root.wavPath];
        recordProcess.running = true;
    }

    function stopRecordingAndSend() {
        recordProcess.running = false;
        VoiceState.phase = "transcribing";
        VoiceState.lastLatency = Object.assign({}, VoiceState.lastLatency, { recordMs: VoiceState.stageDuration("record") });
        VoiceState.markStage("transcribe");
        transcribeProcess.command = ["voice-transcribe", root.wavPath];
        transcribeProcess.running = true;
    }

    Process {
        id: recordProcess
        running: false
    }

    Process {
        id: transcribeProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const heard = text.trim();
                VoiceState.lastLatency = Object.assign({}, VoiceState.lastLatency, { transcribeMs: VoiceState.stageDuration("transcribe") });
                if (heard.length === 0) {
                    VoiceState.errorMessage = "Didn't catch any speech — try again.";
                    VoiceState.phase = "idle";
                    return;
                }
                VoiceState.appendTranscript("user", heard);
                VoiceState.phase = "thinking";
                VoiceState.markStage("llm");
                root._responseText = "";
                if (GooseAcpSession.sessionReady && !GooseAcpSession.busy)
                    GooseAcpSession.prompt(heard);
                else
                    VoiceState.errorMessage = "Chat session isn't ready yet — open the chat overlay once first.";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && VoiceState.phase === "transcribing")
                    console.warn("voice-transcribe stderr:", text);
            }
        }
    }

    property string _responseText: ""

    Connections {
        target: GooseAcpSession
        enabled: VoiceState.phase === "thinking"

        function onMessageChunk(text) {
            root._responseText += text;
        }

        function onTurnComplete(result) {
            if (VoiceState.phase !== "thinking")
                return;
            VoiceState.lastLatency = Object.assign({}, VoiceState.lastLatency, { llmMs: VoiceState.stageDuration("llm") });
            const reply = root._responseText.length > 0 ? root._responseText : "(no response)";
            VoiceState.appendTranscript("assistant", reply);
            VoiceState.phase = "speaking";
            VoiceState.markStage("speak");
            // voice-speak (voice.nix) reads text from stdin until EOF --
            // Process has no stdin-close primitive (same issue as
            // ClipboardTransform.qml's wl-copy, see that file's comment),
            // so piping through a single bash subprocess (printf's own
            // natural EOF closes voice-speak's stdin correctly) avoids
            // needing Process.write()+kill at all.
            speakProcess.command = ["bash", "-c", "printf '%s' \"$1\" | voice-speak", "bash", reply];
            speakProcess.running = true;
        }
    }

    Process {
        id: speakProcess
        running: false
        onExited: (exitCode, exitStatus) => {
            VoiceState.lastLatency = Object.assign({}, VoiceState.lastLatency, { speakMs: VoiceState.stageDuration("speak") });
            VoiceState.phase = "idle";
        }
    }

    // Reactive blob -- radius pulses with live mic peak while recording,
    // gently idles otherwise. Canvas 2D, not a shader (see header comment).
    Canvas {
        id: blob
        anchors.centerIn: parent
        width: 220
        height: 220

        property real idlePhase: 0
        NumberAnimation on idlePhase {
            from: 0
            to: Math.PI * 2
            duration: 3000
            loops: Animation.Infinite
            running: blob.visible
        }

        onIdlePhaseChanged: requestPaint()
        Connections {
            target: VoiceState
            function onMicPeakChanged() {
                blob.requestPaint();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2;
            const cy = height / 2;
            const base = 60;
            const peakBoost = VoiceState.phase === "recording" ? VoiceState.micPeak * 80 : Math.sin(idlePhase) * 6;
            const radius = base + peakBoost;

            const grad = ctx.createRadialGradient(cx, cy, radius * 0.2, cx, cy, radius);
            const color = VoiceState.phase === "recording" ? Theme.color.accentPink : Theme.color.accentPurple;
            grad.addColorStop(0, color);
            grad.addColorStop(1, "transparent");
            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.arc(cx, cy, radius, 0, Math.PI * 2);
            ctx.fill();
        }
    }

    Text {
        anchors {
            top: blob.bottom
            horizontalCenter: blob.horizontalCenter
            topMargin: Theme.spacing.launcherContentGap
        }
        text: {
            switch (VoiceState.phase) {
            case "recording": return "listening… (release Space to send)";
            case "transcribing": return "transcribing…";
            case "thinking": return "qubi is thinking…";
            case "speaking": return "speaking…";
            default: return "hold Space to talk";
            }
        }
        color: Theme.color.launcherPlaceholderFg
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeBase
    }

    Text {
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 40
        }
        visible: VoiceState.errorMessage.length > 0
        text: VoiceState.errorMessage
        color: "#f38ba8"
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
        wrapMode: Text.WordWrap
        width: 400
        horizontalAlignment: Text.AlignHCenter
    }

    // Live two-sided transcript.
    Column {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 60
        }
        width: Theme.spacing.voicePanelWidth + 200
        spacing: Theme.spacing.voiceRowHeight * 0.2

        Repeater {
            model: VoiceState.transcript.slice(-6)
            delegate: Text {
                required property var modelData
                width: parent.width
                horizontalAlignment: modelData.role === "user" ? Text.AlignRight : Text.AlignLeft
                text: modelData.text
                wrapMode: Text.WordWrap
                color: modelData.role === "user" ? Theme.color.fg : Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: Object.keys(VoiceState.lastLatency).length > 0 && VoiceState.phase === "idle"
            text: {
                const l = VoiceState.lastLatency;
                return `record ${l.recordMs ?? 0}ms · transcribe ${l.transcribeMs ?? 0}ms · think ${l.llmMs ?? 0}ms · speak ${l.speakMs ?? 0}ms`;
            }
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            font.italic: true
        }
    }
}
