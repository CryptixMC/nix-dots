import QtQuick
import Quickshell
import Quickshell.Io

// A single independent `goose acp` process, for the side-by-side compare
// view (ChatCompare.qml instantiates two of these). Deliberately NOT
// GooseAcpSession.qml's protocol handling touched or reused directly --
// per this repo's own convention, that file was expensive to derive via
// live probing and stays untouched except for adding signals. This is a
// separate, smaller implementation of the same already-proven protocol
// shape (see GooseAcpSession.qml's own header comment for the confirmed
// framing/method details this reuses): initialize -> session/new -> prompt
// -> streaming updates. Deliberately excludes permission handling,
// mode-switching, subagent routing, and session resume/history replay --
// compare is a side-by-side single-turn-at-a-time experiment, not a full
// session manager, and none of those are needed for that. A real
// session/request_permission arriving here (only possible if GOOSE_MODE
// isn't "auto") is intentionally left unanswered -- see the note on
// `environment` below.
Item {
    id: root

    property string provider: "ollama"
    property string model: ""
    readonly property string defaultCwd: "/home/cryptix/nix-dots"

    property bool sessionReady: false
    property bool busy: false
    property string sessionId: ""

    signal messageChunk(string text)
    signal thoughtChunk(string text)
    signal turnComplete(var result)
    signal sessionFailed(string message)

    property int _nextId: 1
    property var _pending: ({})

    function _send(obj) {
        acpProcess.write(JSON.stringify(obj) + "\n");
    }

    function _call(method, params, callback) {
        const id = root._nextId++;
        root._pending[id] = callback;
        root._send({ jsonrpc: "2.0", id: id, method: method, params: params });
    }

    function start() {
        if (acpProcess.running)
            return;
        acpProcess.environment = {
            "GOOSE_LOCAL_ENABLE_THINKING": "false",
            "GOOSE_PROVIDER": root.provider,
            "GOOSE_MODEL": root.model,
            // Forces auto mode for this pane specifically -- a compare pane
            // has no permission-request UI (see header comment), so a
            // non-auto mode here would just hang forever on the first tool
            // call. Overriding via env rather than assuming config.yaml's
            // default stays auto.
            "GOOSE_MODE": "auto"
        };
        acpProcess.running = true;
    }

    function prompt(text) {
        if (!root.sessionReady || root.busy)
            return;
        root.busy = true;
        _call("session/prompt", {
            sessionId: root.sessionId,
            prompt: [{ type: "text", text: text }]
        }, (result, error) => {
            root.busy = false;
            root.turnComplete(error ? { stopReason: "error", error: error } : result);
        });
    }

    Process {
        id: acpProcess
        command: ["goose", "acp"]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed.length === 0)
                    return;
                let obj;
                try {
                    obj = JSON.parse(trimmed);
                } catch (e) {
                    return;
                }

                if (obj.id !== undefined && (obj.result !== undefined || obj.error !== undefined) && root._pending[obj.id] !== undefined) {
                    const cb = root._pending[obj.id];
                    delete root._pending[obj.id];
                    cb(obj.result, obj.error);
                    return;
                }

                if (obj.method === "session/update") {
                    const upd = obj.params.update;
                    switch (upd.sessionUpdate) {
                    case "agent_message_chunk":
                        root.messageChunk(upd.content.text);
                        break;
                    case "agent_thought_chunk":
                        root.thoughtChunk(upd.content.text);
                        break;
                    }
                }
            }
        }

        onRunningChanged: {
            if (running) {
                root._call("initialize", { protocolVersion: 1 }, (result, error) => {
                    if (error) {
                        root.sessionFailed(`initialize failed: ${JSON.stringify(error)}`);
                        return;
                    }
                    root._call("session/new", { cwd: root.defaultCwd, mcpServers: [] }, (result2, error2) => {
                        if (error2) {
                            root.sessionFailed(`session/new failed: ${JSON.stringify(error2)}`);
                            return;
                        }
                        root.sessionId = result2.sessionId;
                        root.sessionReady = true;
                    });
                });
            }
        }

        onExited: (exitCode, exitStatus) => {
            root._pending = ({});
            root.sessionReady = false;
            root.sessionFailed(`goose acp exited (code ${exitCode})`);
        }
    }
}
