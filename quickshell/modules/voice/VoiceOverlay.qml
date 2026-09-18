import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../../theme"
import "../chat"

// SUPER+O: full-screen voice conversation overlay. Continuous listening
// (energy-threshold voice activity detection on the live mic peak, no
// push-to-talk key) -- still no barge-in: the mic is only actively
// monitored during "listening"/"recording", never while the assistant is
// "thinking"/"speaking", both to avoid the TTS output re-triggering
// itself (no echo cancellation here) and to preserve the original
// no-interrupt-mid-response design intent. Reuses the main
// GooseAcpSession singleton (see VoiceState.qml's header comment for why,
// vs. ChatCompare's genuinely-independent panes).
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
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    readonly property string wavPath: "/tmp/qubi-voice-capture.wav"
    readonly property var micSource: Pipewire.defaultAudioSource

    // Energy-threshold VAD constants -- tuned to reasonable defaults, not
    // calibrated against this specific mic/room (no way to do that without
    // a human actually speaking into it). If it triggers too eagerly on
    // background noise, raise speechThreshold; if it cuts off words early,
    // raise silenceTimeoutMs.
    readonly property real speechThreshold: 0.12
    readonly property real silenceThreshold: 0.06
    readonly property int silenceTimeoutMs: 1200
    readonly property int minUtteranceMs: 400
    readonly property int maxRecordingMs: 30000

    PwObjectTracker {
        objects: root.micSource ? [root.micSource] : []
    }

    PwNodePeakMonitor {
        id: peakMonitor
        node: root.micSource
        enabled: VoiceState.phase === "listening" || VoiceState.phase === "recording"
        onPeakChanged: {
            VoiceState.micPeak = peakMonitor.peak;
            root._onPeak(peakMonitor.peak);
        }
    }

    onVisibleChanged: {
        if (visible) {
            VoiceState.reset();
            VoiceState.phase = "listening";
            VoiceState.markStage("utterance");
            readyCheckProcess.running = true;
        } else {
            if (recordProcess.running)
                recordProcess.running = false;
            silenceTimer.stop();
            maxRecordingTimer.stop();
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
                VoiceState.errorMessage = "Voice models not downloaded yet — the first utterance will trigger the download (whisper ~140MB, piper voice smaller); this may take a moment.";
        }
    }

    // VAD state machine, driven by peakMonitor's live updates.
    function _onPeak(peak) {
        if (VoiceState.phase === "listening") {
            if (peak >= root.speechThreshold)
                root._startRecording();
        } else if (VoiceState.phase === "recording") {
            if (peak >= root.silenceThreshold)
                silenceTimer.restart();
        }
    }

    function _startRecording() {
        VoiceState.phase = "recording";
        VoiceState.markStage("record");
        recordProcess.command = ["pw-record", "--rate", "16000", "--channels", "1", root.wavPath];
        recordProcess.running = true;
        silenceTimer.restart();
        maxRecordingTimer.restart();
    }

    // Fires when silenceTimeoutMs has passed with no peak crossing
    // silenceThreshold -- i.e. the user has stopped talking. Each loud
    // frame above silenceThreshold restarts this timer (see _onPeak), so
    // it only ever actually fires after real, sustained silence.
    Timer {
        id: silenceTimer
        interval: root.silenceTimeoutMs
        onTriggered: root._finishRecording()
    }

    // Safety cap -- if silence detection somehow never fires (e.g.
    // continuous background noise keeping the peak up), don't record
    // forever.
    Timer {
        id: maxRecordingTimer
        interval: root.maxRecordingMs
        onTriggered: root._finishRecording()
    }

    function _finishRecording() {
        if (VoiceState.phase !== "recording")
            return;
        silenceTimer.stop();
        maxRecordingTimer.stop();
        const elapsed = VoiceState.stageDuration("record");
        recordProcess.running = false;
        if (elapsed < root.minUtteranceMs) {
            // Too short to be real speech (a click, a cough) -- discard
            // and keep listening rather than round-tripping whisper on
            // near-silence.
            VoiceState.phase = "listening";
            VoiceState.markStage("utterance");
            return;
        }
        VoiceState.phase = "transcribing";
        VoiceState.lastLatency = Object.assign({}, VoiceState.lastLatency, { recordMs: elapsed });
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
                    // Nothing intelligible -- likely a false VAD trigger
                    // (background noise). Go straight back to listening,
                    // no error shown -- an error message for every false
                    // trigger would be noisy for a continuous-listening
                    // design in a way it never was for push-to-talk.
                    VoiceState.phase = "listening";
                    VoiceState.markStage("utterance");
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
            // Back to listening automatically -- continuous conversation,
            // no key needed to re-arm.
            VoiceState.phase = "listening";
            VoiceState.markStage("utterance");
        }
    }

    // Reactive waveform: a row of bars, each independently animated.
    // Deliberately not a single Canvas-drawn blob (the previous design) --
    // that had a real, reported bug where the blob's radius formula could
    // exceed its own canvas bounds and visibly clip. A Row of plain
    // Rectangles with Behavior-animated heights can't clip the same way
    // (each bar's height is just capped, never drawn past its own
    // bounds), renders more crisply, and reads closer to a real audio
    // waveform / Claude-mobile-style voice indicator than a pulsing
    // circle did.
    Item {
        id: waveform
        anchors.centerIn: parent
        width: Theme.spacing.voiceWaveformWidth
        height: Theme.spacing.voiceWaveformHeight

        readonly property int barCount: 28
        readonly property real barSpacing: 5

        Row {
            anchors.centerIn: parent
            spacing: waveform.barSpacing

            Repeater {
                model: waveform.barCount
                delegate: Rectangle {
                    id: bar
                    required property int index

                    // Static per-bar phase/seed so each bar's idle motion
                    // and noise response looks distinct, not a uniform
                    // pulse -- part of the "dynamic, not static" ask.
                    readonly property real seed: (index * 0.6180339887) % 1.0
                    property real targetHeight: 4

                    width: 4
                    radius: 2
                    height: targetHeight
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        const c = Theme.color.accentPurple;
                        if (VoiceState.phase === "speaking")
                            return c;
                        if (VoiceState.phase === "recording")
                            return Theme.color.accentPink;
                        return Qt.rgba(c.r, c.g, c.b, 0.5);
                    }

                    Behavior on height {
                        NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }
            }
        }
    }

    // Drives each bar's targetHeight. A single shared timer rather than
    // one per bar -- 30fps is plenty smooth given the Behavior animation
    // above eases between steps anyway, and is a lot cheaper than 28
    // independent timers.
    Timer {
        interval: 33
        running: root.visible
        repeat: true
        property real t: 0
        onTriggered: {
            t += 0.12;
            const bars = waveform.children[0].children;
            const level = VoiceState.phase === "recording" ? VoiceState.micPeak
                : VoiceState.phase === "speaking" ? 0.5 + 0.3 * Math.sin(t * 3)
                : 0.08;
            for (let i = 0; i < bars.length; i++) {
                const bar = bars[i];
                if (bar.seed === undefined)
                    continue;
                const wave = Math.sin(t * 2 + bar.seed * Math.PI * 4);
                const noise = VoiceState.phase === "recording" ? (Math.sin(t * 9 + bar.seed * 17) * 0.5 + 0.5) : 0.5;
                const amplitude = 6 + level * 90 * (0.4 + 0.6 * noise);
                bar.targetHeight = Math.max(4, Math.min(waveform.height, 6 + amplitude * (0.5 + 0.5 * wave)));
            }
        }
    }

    Text {
        anchors {
            top: waveform.bottom
            horizontalCenter: waveform.horizontalCenter
            topMargin: Theme.spacing.launcherContentGap
        }
        text: {
            switch (VoiceState.phase) {
            case "listening": return "listening…";
            case "recording": return "hearing you…";
            case "transcribing": return "transcribing…";
            case "thinking": return "qubi is thinking…";
            case "speaking": return "speaking…";
            default: return "";
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
            visible: Object.keys(VoiceState.lastLatency).length > 0 && VoiceState.phase === "listening"
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
