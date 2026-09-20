pragma Singleton
import QtQuick

// phase: "idle" -> "recording" -> "transcribing" -> "thinking" -> "speaking" -> "idle"
// Push-to-talk only -- no barge-in, no continuous listening. Reuses the
// main GooseAcpSession singleton rather than a third independent ACP
// implementation (unlike ChatCompare, which genuinely needs two
// *simultaneous* independent sessions, voice is a single serialized
// conversation same as the chat overlay -- reusing the proven session
// avoids needless duplication, at the documented cost of interleaving if
// both the chat overlay and voice mode are actively used at the same
// moment, a real but acceptable v1 limitation).
QtObject {
    id: root

    property bool visible: false
    property string phase: "idle"
    property var transcript: []
    property string errorMessage: ""
    property real micPeak: 0

    // Per-stage timing for the "measure and report real latency"
    // requirement -- populated once a full turn completes.
    property var lastLatency: ({})
    property var _stageStarts: ({})

    function markStage(name) {
        const copy = Object.assign({}, root._stageStarts);
        copy[name] = Date.now();
        root._stageStarts = copy;
    }

    function stageDuration(name) {
        return root._stageStarts[name] !== undefined ? Date.now() - root._stageStarts[name] : 0;
    }

    function appendTranscript(role, text) {
        root.transcript = root.transcript.concat([{ role: role, text: text }]);
    }

    function reset() {
        root.phase = "idle";
        root.errorMessage = "";
    }

    function hide() {
        root.visible = false;
        root.phase = "idle";
    }
}
