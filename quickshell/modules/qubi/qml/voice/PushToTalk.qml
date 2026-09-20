import QtQuick
import Quickshell.Io

// Hold-to-talk capture for the chat composer's mic button.
//
// Deliberately NOT the same path as VoiceOverlay.qml. That one is a
// continuous-listening conversation: a VAD state machine decides when an
// utterance started and ended, and the transcript is handed straight to
// GooseAcpSession.prompt(). This one is the opposite -- the human decides
// the boundaries by holding a button, and the transcript is handed back
// to the caller as editable text that is NOT sent anywhere. Same two
// underlying tools (`pw-record`, then `voice-transcribe`, the whisper-cpp
// wrapper from modules/home-manager/apps/voice.nix), no VAD in between.
//
// VoiceOverlay keeps its own copy of the record/transcribe plumbing
// rather than being refactored onto this: the two differ in when they
// stop and what they do with the result, so sharing would mean
// parameterising the interesting part away.
Item {
    id: root

    // Separate wav from VoiceOverlay's /tmp/qubi-voice-capture.wav so a
    // held mic button and a running conversation can never overwrite each
    // other's audio mid-capture.
    readonly property string wavPath: "/tmp/qubi-ptt-capture.wav"
    readonly property int maxRecordingMs: 60000

    property bool recording: false
    property bool transcribing: false

    signal transcribed(string text)

    function start() {
        if (root.recording || root.transcribing)
            return;
        root.recording = true;
        recordProcess.command = ["pw-record", "--rate", "16000", "--channels", "1", root.wavPath];
        recordProcess.running = true;
        maxRecordingTimer.restart();
    }

    function stop() {
        if (!root.recording)
            return;
        maxRecordingTimer.stop();
        root.recording = false;
        recordProcess.running = false;
        root.transcribing = true;
        transcribeProcess.command = ["voice-transcribe", root.wavPath];
        transcribeProcess.running = true;
    }

    // Safety cap: a press whose release is somehow never delivered would
    // otherwise leave pw-record running indefinitely.
    Timer {
        id: maxRecordingTimer
        interval: root.maxRecordingMs
        onTriggered: root.stop()
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
                root.transcribing = false;
                const heard = text.trim();
                // Silence or an unintelligible clip yields an empty
                // transcript -- emit nothing rather than an empty insert.
                if (heard.length > 0)
                    root.transcribed(heard);
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    console.warn("PushToTalk: voice-transcribe stderr:", text);
            }
        }
    }
}
