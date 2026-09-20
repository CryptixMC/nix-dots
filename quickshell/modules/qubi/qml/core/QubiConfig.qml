pragma Singleton
import QtQuick
import Quickshell

// Every host-specific location/endpoint Qubi's QML touches, resolved in one
// place -- the QML counterpart of python/src/qubi/paths.py, reading the same
// QUBI_* environment variables. Precedence: `overrides` (set by the
// embedding shell, see Qubi.qml's `config` property), then the environment,
// then a default that names no user, uid or checkout.
QtObject {
    id: root

    property var overrides: ({})

    // Major version of the qubi/* protocol this QML speaks; compared with
    // what the engine reports in qubi/status (python/src/qubi/protocol.py).
    readonly property int protocolMajor: 1

    function _pick(key, envName, fallback) {
        const o = root.overrides ? root.overrides[key] : undefined;
        if (o !== undefined && o !== null && o !== "")
            return o;
        const e = envName ? Quickshell.env(envName) : null;
        return (e !== undefined && e !== null && e !== "") ? e : fallback;
    }

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || `${root.home}/.config`
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || `${root.home}/.local/share`

    readonly property string socketPath: root._pick("socketPath", "QUBI_SOCKET", `${root.runtimeDir}/qubi/engine.sock`)
    // Working directory new goose sessions are created in.
    readonly property string defaultCwd: root._pick("defaultCwd", "QUBI_DEFAULT_CWD", root.home)
    readonly property string ollamaUrl: root._pick("ollamaUrl", "QUBI_OLLAMA_URL", "http://127.0.0.1:11434")
    // Optional; see docs/hw-state.md. A missing file means "docked".
    readonly property string hwStateFile: root._pick("hwStateFile", "QUBI_HW_STATE_FILE", "/run/qubi/hw-state.json")
    readonly property string gooseConfigPath: root._pick("gooseConfigPath", "QUBI_GOOSE_CONFIG", `${root.configHome}/goose/config.yaml`)
    readonly property string sessionsDbPath: root._pick("sessionsDbPath", "QUBI_GOOSE_SESSIONS_DB", `${root.dataHome}/goose/sessions/sessions.db`)
    // Matches python/src/qubi/mcp/ask_user.py, which does not follow XDG_DATA_HOME.
    readonly property string askUserDir: `${root.home}/.local/share/qubi/ask-user`
}
