pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Persistent `goose acp` JSON-RPC-over-stdio session — replaces the old
// one-`goose run`-process-per-message model with a single long-lived
// process, following the real Agent Client Protocol (Zed's ACP spec) Goose
// implements. Every method/type name and framing detail here was confirmed
// live this session via a hand-written JSON-RPC probe against the real
// installed `goose` binary before writing any of this QML (see TODO.md §7
// and the chat-expansion plan doc) — not guessed from the public spec:
//
// - Framing is bare newline-delimited JSON (no LSP-style Content-Length
//   headers) — confirmed by reading real responses back.
// - `initialize` only strictly requires `protocolVersion` (int, `1` today).
// - `session/new` requires `cwd`; `mcpServers` accepted as an empty list.
// - `session/set_mode` is genuinely live (no process respawn) — confirmed
//   via a real `current_mode_update` notification and an immediate result.
// - `session/request_permission` arrives as a real agent-initiated request
//   (note: its own `id` is a UUID *string*, unlike our own integer request
//   ids) and genuinely gates tool execution — confirmed by holding a real
//   `echo` shell tool call pending, responding `allow_once`, and watching
//   real stdout + a `completed` tool_call_update arrive only afterward.
// - `agent_message_chunk` / `agent_thought_chunk` / `tool_call` /
//   `tool_call_update` are the real `session/update` content-kind values.
//   `agent_thought_chunk` is model-dependent — a non-reasoning model (e.g.
//   qwen2.5-coder) simply never emits one; don't treat its absence as a
//   protocol failure.
//
// Process.write()/stdinEnabled are real, confirmed against the installed
// Quickshell qmltypes (quickshell-io.qmltypes) rather than assumed.
Item {
    id: root

    readonly property string defaultCwd: "/home/cryptix/nix-dots"

    property bool initialized: false
    property string sessionId: ""
    property bool sessionReady: false
    property string currentModeId: "auto"
    property var availableModes: []
    property var configOptions: []
    property bool busy: false
    property string subagentProvider: ""
    property string subagentModel: ""
    // Tracks the live primary provider/model so subagent restarts can preserve them.
    property string _currentProvider: ""
    property string _currentModel: ""

    signal messageChunk(string text)
    signal thoughtChunk(string text)
    signal toolCall(var call)
    signal toolCallUpdate(var update)
    signal turnComplete(var result)
    signal permissionRequested(var request)
    signal sessionFailed(string message)
    // Fired once per historical turn while session/load replays a resumed
    // session's prior conversation (role: "user"/"assistant") — each event
    // is that turn's complete text, not a streaming delta, unlike
    // messageChunk/thoughtChunk during a live in-flight turn.
    signal historyMessage(string role, string text)
    signal historyLoaded

    property int _nextId: 1
    property var _pending: ({})
    property bool _loadingHistory: false
    property bool _emitHistoryReplay: true
    // Set just before an intentional stop+relaunch (model switch) so
    // onExited restarts the process and resumes the same session instead
    // of treating it as a crash.
    property bool _restarting: false
    property string _resumeAfterRestart: ""
    property var _switchCallback: null

    function _send(obj) {
        acpProcess.write(JSON.stringify(obj) + "\n");
    }

    function _call(method, params, callback) {
        const id = root._nextId++;
        root._pending[id] = callback;
        root._send({
            jsonrpc: "2.0",
            id: id,
            method: method,
            params: params
        });
    }

    function start() {
        if (acpProcess.running)
            return;
        acpProcess.running = true;
    }

    function _initialize() {
        _call("initialize", {
            protocolVersion: 1
        }, (result, error) => {
            if (error) {
                root.sessionFailed(`initialize failed: ${JSON.stringify(error)}`);
                return;
            }
            root.initialized = true;
            if (root._resumeAfterRestart.length > 0) {
                const id = root._resumeAfterRestart;
                const cb = root._switchCallback;
                root._resumeAfterRestart = "";
                root._switchCallback = null;
                // The UI already shows this conversation's history from
                // before the switch — replaying it again would duplicate
                // every message, so emitHistory is false here specifically
                // (contrast SessionsPicker's resume, which starts from a
                // cleared chat and wants the replay).
                root.loadSession(id, cb, false);
            } else {
                root._newSession();
            }
        });
    }

    function _newSession() {
        _call("session/new", {
            cwd: root.defaultCwd,
            mcpServers: []
        }, (result, error) => {
            if (error) {
                root.sessionFailed(`session/new failed: ${JSON.stringify(error)}`);
                return;
            }
            root.sessionId = result.sessionId;
            root.currentModeId = result.modes.currentModeId;
            root.availableModes = result.modes.availableModes;
            root.configOptions = result.configOptions ?? [];
            const _provider0 = root.configOptions.find(o => o.id === "provider");
            const _model0 = root.configOptions.find(o => o.id === "model");
            if (_provider0)
                root._currentProvider = _provider0.currentValue;
            if (_model0)
                root._currentModel = _model0.currentValue;
            root.sessionReady = true;
        });
    }

    // text: plain string turn from the user. Streamed response arrives via
    // messageChunk/thoughtChunk/toolCall/toolCallUpdate signals; turnComplete
    // fires once with the final stopReason/usage.
    function prompt(text) {
        if (!root.sessionReady || root.busy)
            return;
        root.busy = true;
        _call("session/prompt", {
            sessionId: root.sessionId,
            prompt: [{
                type: "text",
                text: text
            }]
        }, (result, error) => {
            root.busy = false;
            root.turnComplete(error ? {
                stopReason: "error",
                error: error
            } : result);
        });
    }

    // Real ACP capability, not the CLI's `goose session list` — that
    // command only shows session_type:"user" sessions and silently
    // excludes every session_type:"acp" one (confirmed live by comparing
    // its output against the raw sessions.db: 6 vs. 48 rows), which is
    // exactly what every session this chat overlay creates is. session/list
    // needs no active session and works before session/new has ever run.
    function listSessions(callback) {
        _call("session/list", {}, (result, error) => {
            callback(error ? [] : (result.sessions ?? []), error);
        });
    }

    // Resumes an existing session by id, replacing whatever session is
    // currently active. Replays full prior history via historyMessage
    // signals (see session/load's confirmed behavior) before resolving;
    // callback fires once modes/configOptions are known, same shape as a
    // fresh session/new. emitHistory=false suppresses the historyMessage
    // signals entirely (used by switchModel's post-restart resume, where
    // the UI already has this conversation displayed).
    function loadSession(sessionId, callback, emitHistory) {
        root.sessionReady = false;
        root._loadingHistory = true;
        root._emitHistoryReplay = emitHistory ?? true;
        _call("session/load", {
            sessionId: sessionId,
            cwd: root.defaultCwd,
            mcpServers: []
        }, (result, error) => {
            root._loadingHistory = false;
            root.historyLoaded();
            if (error) {
                root.sessionFailed(`session/load failed: ${JSON.stringify(error)}`);
                if (callback)
                    callback(error);
                return;
            }
            root.sessionId = sessionId;
            root.currentModeId = result.modes.currentModeId;
            root.availableModes = result.modes.availableModes;
            root.configOptions = result.configOptions ?? [];
            const _provider0 = root.configOptions.find(o => o.id === "provider");
            const _model0 = root.configOptions.find(o => o.id === "model");
            if (_provider0)
                root._currentProvider = _provider0.currentValue;
            if (_model0)
                root._currentModel = _model0.currentValue;
            root.sessionReady = true;
            if (callback)
                callback(null);
        });
    }

    function setMode(modeId) {
        if (!root.sessionReady)
            return;
        _call("session/set_mode", {
            sessionId: root.sessionId,
            modeId: modeId
        }, () => {});
    }

    // Live model switching mid-conversation: `session/set_config` exists as
    // a literal string in the compiled binary but returns a real
    // `-32601 Method not found` when actually called — confirmed live, not
    // assumed — so there's no live-set path. Instead: stop the process,
    // relaunch with GOOSE_PROVIDER/GOOSE_MODEL overridden via the child's
    // own environment (not touching config.yaml at all), then
    // session/load the same sessionId to resume with history intact.
    // `Process.environment` merges over the inherited environment rather
    // than replacing it (clearEnvironment defaults false), so PATH etc.
    // survive.
    function switchModel(provider, model, callback) {
        if (!root.sessionReady)
            return;
        root._currentProvider = provider;
        root._currentModel = model;
        root._resumeAfterRestart = root.sessionId;
        root._switchCallback = callback ?? null;
        root._restarting = true;
        const env = {
            "GOOSE_PROVIDER": provider,
            "GOOSE_MODEL": model,
            "GOOSE_LOCAL_ENABLE_THINKING": "false"
        };
        if (root.subagentProvider !== "") {
            env["GOOSE_SUBAGENT_PROVIDER"] = root.subagentProvider;
            env["GOOSE_SUBAGENT_MODEL"] = root.subagentModel;
        }
        acpProcess.environment = env;
        root.sessionReady = false;
        acpProcess.running = false;
    }

    function switchSubagentModel(provider, model, callback) {
        root.subagentProvider = provider;
        root.subagentModel = model;
        root._resumeAfterRestart = root.sessionId;
        root._switchCallback = callback ?? null;
        root._restarting = true;
        const env = {
            "GOOSE_PROVIDER": root._currentProvider,
            "GOOSE_MODEL": root._currentModel,
            "GOOSE_SUBAGENT_PROVIDER": provider,
            "GOOSE_SUBAGENT_MODEL": model,
            "GOOSE_LOCAL_ENABLE_THINKING": "false"
        };
        acpProcess.environment = env;
        root.sessionReady = false;
        acpProcess.running = false;
    }

    // Lets qubi-state-sync (a root-context systemd oneshot on dock-undock)
    // trigger a live model switch without touching config.yaml, via
    // `quickshell ipc -p ~/nix-dots/quickshell call qubi-model switchModel
    // <provider> <model>` — same IpcHandler convention ChatOverlay.qml
    // already uses for its "chat"/toggle target.
    IpcHandler {
        target: "qubi-model"
        function switchModel(provider: string, model: string): void {
            root.switchModel(provider, model);
        }
        function switchSubagentModel(provider: string, model: string): void {
            root.switchSubagentModel(provider, model);
        }
    }

    function cancel() {
        if (!root.sessionReady)
            return;
        _call("session/cancel", {
            sessionId: root.sessionId
        }, () => {});
    }

    // requestId: the UUID string from the incoming session/request_permission
    // request (echoed back verbatim, per JSON-RPC). optionId: one of the
    // option ids the request itself listed (e.g. "allow_once", "allow_always",
    // "reject_once").
    function respondToPermission(requestId, optionId) {
        root._send({
            jsonrpc: "2.0",
            id: requestId,
            result: {
                outcome: {
                    outcome: "selected",
                    optionId: optionId
                }
            }
        });
    }

    Process {
        id: acpProcess
        command: ["goose", "acp"]
        stdinEnabled: true
        // Part II Stage 3: measured faster in every directly comparable
        // benchmark cell with no accuracy loss (e.g. 928s -> 71s on one
        // qwen3-coder task) — the chat overlay is interactive, so
        // responsiveness wins by default. switchModel below re-asserts this
        // on every relaunch since Process.environment is replaced wholesale,
        // not merged key-by-key, on each assignment.
        environment: ({
            "GOOSE_LOCAL_ENABLE_THINKING": "false"
        })

        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed.length === 0)
                    return;
                let obj;
                try {
                    obj = JSON.parse(trimmed);
                } catch (e) {
                    console.warn("GooseAcpSession: failed to parse line as JSON:", trimmed);
                    return;
                }

                // Response to one of our own requests (integer id we issued).
                if (obj.id !== undefined && (obj.result !== undefined || obj.error !== undefined) && root._pending[obj.id] !== undefined) {
                    const cb = root._pending[obj.id];
                    delete root._pending[obj.id];
                    cb(obj.result, obj.error);
                    return;
                }

                // Agent-initiated request needing a response from us.
                if (obj.method === "session/request_permission") {
                    root.permissionRequested(obj);
                    return;
                }

                // Notification stream.
                if (obj.method === "session/update") {
                    const upd = obj.params.update;
                    switch (upd.sessionUpdate) {
                    case "user_message_chunk":
                        // Only ever observed during session/load's history
                        // replay (a live turn never echoes the caller's own
                        // message back) — each event is one complete past
                        // turn, not a delta.
                        if (root._loadingHistory && root._emitHistoryReplay)
                            root.historyMessage("user", upd.content.text);
                        break;
                    case "agent_message_chunk":
                        if (root._loadingHistory) {
                            if (root._emitHistoryReplay)
                                root.historyMessage("assistant", upd.content.text);
                        } else
                            root.messageChunk(upd.content.text);
                        break;
                    case "agent_thought_chunk":
                        root.thoughtChunk(upd.content.text);
                        break;
                    case "tool_call":
                        root.toolCall(upd);
                        break;
                    case "tool_call_update":
                        root.toolCallUpdate(upd);
                        break;
                    case "current_mode_update":
                        root.currentModeId = upd.currentModeId;
                        break;
                    }
                }
            }
        }

        onRunningChanged: {
            if (running)
                root._initialize();
        }

        onExited: (exitCode, exitStatus) => {
            root._pending = ({});
            if (root._restarting) {
                root._restarting = false;
                acpProcess.running = true;
                return;
            }
            root.initialized = false;
            root.sessionReady = false;
            root.sessionId = "";
            root.sessionFailed(`goose acp exited (code ${exitCode})`);
        }
    }
}
