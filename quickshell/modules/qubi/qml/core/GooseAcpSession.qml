pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Talks the real Agent Client Protocol (Zed's ACP spec, as Goose
// implements it) over a Unix socket to qubi-engine instead of spawning
// `goose acp` directly -- Phase 8a of the qubi-engine night. EVERY
// protocol detail below (framing, method names, notification shapes) is
// UNCHANGED from the original stdio-Process version; only the transport
// (Socket instead of Process) is different, confirmed correct live via a
// staging round-trip (~/qubi-staging/engine's socket test, before this
// file was touched): a real Socket connected to $XDG_RUNTIME_DIR/qubi/
// engine.sock, sent a real qubi/status request, and got the real engine's
// JSON response back through a SplitParser exactly like Process.stdout
// already used. The engine itself is a transparent ACP proxy (see
// engine/qubi_engine.py's own header comment) -- from this file's
// perspective, nothing about session/new, session/prompt, session/update
// notifications, or permission requests differs from talking to `goose
// acp` directly.
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
// - New in this engine-backed version: `qubi/session_status` and
//   `qubi/escalation_offer` are engine-originated notifications (never
//   sent by a bare `goose acp` process) — surfaced as their own signals
//   below, additive to the unchanged ACP signal set.
Item {
    id: root

    readonly property string defaultCwd: QubiConfig.defaultCwd
    readonly property string _engineSocketPath: QubiConfig.socketPath

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
    // True once the engine socket has genuinely refused/dropped a
    // connection -- lets the UI show a real "engine not running" state
    // with a retry action instead of hanging silently forever (Phase 8a's
    // explicit requirement).
    property bool engineUnavailable: false

    // Live activity phase for THIS session, straight off the engine's
    // qubi/session_status stream. `busy` is a binary in-flight flag and
    // cannot tell "spawning a cold multi-GB model" apart from "generating
    // token 400" -- measured on a real docked turn, the panel had no new
    // information for 48 seconds before the first output arrived, which is
    // what "it looks frozen" actually is. These name the step, and
    // phaseDetail carries a rolling fragment of what the model is reasoning
    // about, derived by the engine from the reasoning stream it already has
    // (no second model call).
    property string phase: "idle"
    property string phaseDetail: ""

    signal qubiSessionStatus(var status)
    signal qubiEscalationOffer(var offer)

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
    // Set on a real (unrequested) socket disconnect when a session was
    // active, so the next successful reconnect resumes it via
    // session/load instead of starting a brand new session — the engine
    // restarting (Restart=on-failure) doesn't necessarily lose Goose's own
    // sqlite-persisted session history even though it does lose the
    // engine's in-memory session/tier bookkeeping.
    property string _resumeAfterRestart: ""
    // modelName -> tierName, built from a real qubi/status reply right
    // after connecting -- lets switchModel (below) route a model pick to
    // the one real engine capability that exists for it (qubi/set_tier)
    // instead of guessing tier names from config.json's shape.
    property var _tierModels: ({})
    // tierName -> model name, the inverse of _tierModels above. Drives the
    // chat status bar's "light · qwen3:4b" readout so it names the model
    // the engine is really running for this tier rather than echoing a
    // client-side guess.
    property var tierModels: ({})
    // Which tier this session is actually bound to. The engine is the
    // authority (it reports this on every qubi/session_status push); the
    // "light" default matches qubi_engine.py's own _new_session_on("light").
    property string currentTier: "light"
    // How many history turns the last session/load actually replayed.
    // Measured because the replay is NOT dependable: against the live
    // engine, some sessions replay their history and others -- including
    // ones with real messages in the db -- replay nothing and resume to a
    // blank panel. A consumer can use this to fall back to the database.
    property int historyReplayCount: 0

    function _send(obj) {
        acpSocket.write(JSON.stringify(obj) + "\n");
        acpSocket.flush();
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
        if (acpSocket.connected)
            return;
        root.engineUnavailable = false;
        acpSocket.connected = true;
    }

    // Real retry path for the "engine not running" UI state -- toggling
    // `connected` false->true asks Quickshell.Io.Socket to attempt a fresh
    // connection (confirmed live: the identical pattern reconnected to
    // qubi-engine.service after a manual `systemctl --user restart` during
    // this session's own staging tests).
    function retryConnect() {
        root.engineUnavailable = false;
        acpSocket.connected = false;
        acpSocket.connected = true;
    }

    function _fetchTierModels() {
        _call("qubi/status", {}, (result, error) => {
            if (error || !result)
                return;
            const map = {};
            const byTier = {};
            for (const tierName in result.tiers ?? {}) {
                map[result.tiers[tierName].model] = tierName;
                byTier[tierName] = result.tiers[tierName].model;
            }
            root._tierModels = map;
            root.tierModels = byTier;
        });
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
            root._fetchTierModels();
            if (root._resumeAfterRestart.length > 0) {
                const id = root._resumeAfterRestart;
                root._resumeAfterRestart = "";
                // The UI already shows this conversation's history from
                // before the disconnect — replaying it again would
                // duplicate every message, so emitHistory is false here
                // specifically (contrast SessionsPicker's resume, which
                // starts from a cleared chat and wants the replay).
                root.loadSession(id, null, false);
            } else {
                root._newSession();
            }
        });
    }

    // Public entry point for starting a fresh conversation on demand
    // (the composer's /new command). Same call the initial connect makes.
    function newSession() {
        root._newSession();
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
        root.historyReplayCount = 0;
        root._emitHistoryReplay = emitHistory ?? true;
        _call("session/load", {
            sessionId: sessionId,
            cwd: root.defaultCwd,
            mcpServers: []
        }, (result, error) => {
            root._loadingHistory = false;
            if (error) {
                root.historyLoaded();
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
            // Emitted only now, AFTER sessionId and the rest of the
            // session state are current. It used to fire first, which
            // meant any handler asking "which session just loaded?" got
            // the PREVIOUS one -- harmless for the buffer-flush consumer
            // that existed then, but wrong for anything that acts on the
            // resumed session (the db backfill reads exactly this id).
            root.historyLoaded();
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

    // Pre-engine, this restarted our own `goose acp` process with
    // GOOSE_PROVIDER/GOOSE_MODEL overridden in its environment -- that
    // process no longer exists on this side of the socket, qubi-engine
    // owns it per-tier now, and the engine exposes no per-request
    // provider/model override (only whole-tier switching via
    // qubi/set_tier, confirmed by reading qubi_engine.py's own
    // _handle_qubi_method — status/theme/session_list/subscribe/set_tier
    // is the complete method list, nothing else). Since each tier in
    // ~/.config/qubi/config.json is exactly one fixed model, a model pick
    // maps onto a real tier switch whenever that model IS a tier's model
    // (root._tierModels, populated from a live qubi/status reply); a pick
    // that isn't any tier's model (e.g. goose.nix's docked qwen3.6 pick,
    // which predates the engine and isn't one of the 3 tier models) has no
    // engine equivalent today and fails honestly via sessionFailed rather
    // than silently doing nothing.
    function switchModel(provider, model, callback) {
        if (!root.sessionReady)
            return;
        const tier = root._tierModels[model];
        if (tier === undefined) {
            const msg = `no engine tier runs model "${model}" — only whole-tier switching is available now (see GooseAcpSession.qml's switchModel comment)`;
            root.sessionFailed(msg);
            if (callback)
                callback({
                    code: -32601,
                    message: msg
                });
            return;
        }
        root.setTier(root.sessionId, tier, callback);
    }

    // Subagent provider/model overrides had no ACP-level representation
    // even before the engine (they were a Goose-process env var); the
    // engine's tiers carry no subagent notion at all, so there is no
    // equivalent to route this to. Surfaced honestly instead of pretending
    // to switch.
    function switchSubagentModel(provider, model, callback) {
        const msg = "subagent model switching is not available on the engine-backed session (no per-tier subagent concept — see GooseAcpSession.qml's switchSubagentModel comment)";
        root.sessionFailed(msg);
        if (callback)
            callback({
                code: -32601,
                message: msg
            });
    }

    // The one real live-switch capability the engine exposes: rebinds a
    // session to a different tier's already-running process via
    // session/load (resuming history), confirmed by reading qubi_engine.py's
    // _set_tier. Also the target of the escalation-offer chip's
    // escalate_claude/escalate_heavy_local buttons (see respondToEscalation).
    function setTier(sessionId, tier, callback) {
        _call("qubi/set_tier", {
            session: sessionId,
            tier: tier
        }, (result, error) => {
            if (error) {
                root.sessionFailed(`qubi/set_tier failed: ${JSON.stringify(error)}`);
                if (callback)
                    callback(error);
                return;
            }
            // Reflect it immediately rather than waiting for the engine's
            // next qubi/session_status push -- set_tier only resolves
            // after a real session/load onto the target tier, so by this
            // point the switch has genuinely happened.
            if (sessionId === root.sessionId)
                root.currentTier = tier;
            if (callback)
                callback(null);
        });
    }

    // Every model Ollama has locally. Used by the model browser's
    // "installed" list so picking an already-downloaded model doesn't
    // require it to appear in llmfit's recommendation feed first.
    function installedModels(callback) {
        _call("qubi/installed_models", {}, (result, error) => {
            callback(error ? [] : (result?.models ?? []), error ?? null);
        });
    }

    // Use a specific installed model for THIS conversation, right now.
    // Deliberately not a config change: the engine binds this session onto
    // an ephemeral per-model tier and leaves every named tier's own
    // configured model untouched (see qubi_engine.py's _use_model). Picking
    // a model from the browser must not silently reassign what "light" or
    // "fast" mean for every other conversation.
    function useModelNow(model, callback) {
        _call("qubi/use_model", {
            session: root.sessionId,
            model: model
        }, (result, error) => {
            if (error) {
                root.sessionFailed(`qubi/use_model failed: ${JSON.stringify(error)}`);
                if (callback)
                    callback(error);
                return;
            }
            // currentTier updates itself from the qubi/session_status push
            // this switch triggers server-side -- no local bookkeeping
            // needed here beyond the callback.
            if (callback)
                callback(null);
        });
    }

    // options offered by a real qubi/escalation_offer notification are
    // exactly ["escalate_claude", "escalate_heavy_local", "decline"]
    // (qubi_engine.py's _on_tier_notification) -- decline needs no engine
    // call, the offer simply isn't acted on.
    function respondToEscalation(sessionId, optionId) {
        if (optionId === "escalate_claude")
            root.setTier(sessionId, "claude");
        else if (optionId === "escalate_heavy_local")
            root.setTier(sessionId, "heavy");
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

    Socket {
        id: acpSocket
        path: root._engineSocketPath

        parser: SplitParser {
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

                // Engine-originated notifications — never sent by a bare
                // `goose acp` process, only by qubi-engine itself
                // (qubi_engine.py's _push_status / escalation-offer path).
                if (obj.method === "qubi/session_status") {
                    // Only adopt the tier when the push is about OUR
                    // session -- the engine fans these out per-subscriber,
                    // but once this client subscribes to other sessions
                    // (live-sync) an unrelated session's tier must not
                    // overwrite the status bar.
                    if (obj.params.session === root.sessionId && obj.params.tier)
                        root.currentTier = obj.params.tier;
                    // Same per-session guard as currentTier above: another
                    // subscribed session's phase must not drive this panel's
                    // indicator.
                    if (obj.params.session === root.sessionId) {
                        root.phase = obj.params.phase ?? "idle";
                        root.phaseDetail = obj.params.phaseDetail ?? "";
                    }
                    root.qubiSessionStatus(obj.params);
                    return;
                }
                if (obj.method === "qubi/escalation_offer") {
                    root.qubiEscalationOffer(obj.params);
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
                        if (root._loadingHistory) {
                            root.historyReplayCount++;
                            if (root._emitHistoryReplay)
                                root.historyMessage("user", upd.content.text);
                        }
                        break;
                    case "agent_message_chunk":
                        if (root._loadingHistory) {
                            root.historyReplayCount++;
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

        onConnectionStateChanged: {
            if (acpSocket.connected) {
                root.engineUnavailable = false;
                root._initialize();
                return;
            }
            // Real disconnect (engine restarted, engine.service down, or a
            // manual retryConnect mid-flight) — never silently hang: drop
            // in-flight callbacks, mark state not-ready, and surface a
            // real user-visible error via the same sessionFailed path
            // ChatOverlay.qml already renders as an assistant-bubble
            // message (confirmed by reading its onSessionFailed handler).
            root._pending = ({});
            if (root.sessionId.length > 0)
                root._resumeAfterRestart = root.sessionId;
            root.initialized = false;
            root.sessionReady = false;
            root.engineUnavailable = true;
            root.sessionFailed("qubi engine connection lost (is qubi-engine.service running?) — retry to reconnect");
        }

        onError: error => {
            root.engineUnavailable = true;
            root.sessionFailed(`qubi engine socket error: ${error} (is qubi-engine.service running?)`);
        }
    }
}
