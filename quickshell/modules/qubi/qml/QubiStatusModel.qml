import QtQuick
import Quickshell
import Quickshell.Io
import "core"

// Engine health at a glance, with no opinion about how it is drawn: a host
// bar binds `state`/`body`/`hint` to its own widget (see nix-dots'
// modules/bar/QubiStatus.qml for a ~15-line example). Own standalone
// qubi/status poll -- NOT GooseAcpSession, which creates a real chat
// session on start(). A Scope, not an Item: it must not take part in the
// host widget's layout.
Scope {
    id: root

    // off|gaming|warming|idle|light|heavy|claude
    property string state: "off"
    property var lastStatus: null
    // True once the engine has reported a protocol major this QML does not
    // speak (python/src/qubi/protocol.py vs QubiConfig.protocolMajor).
    readonly property bool protocolMismatch: root.lastStatus?.protocol !== undefined
        && root.lastStatus.protocol.major !== QubiConfig.protocolMajor

    readonly property string title: "QUBI"
    readonly property string body: {
        const t = root.lastStatus?.tiers;
        if (root.protocolMismatch)
            return `engine speaks protocol ${root.lastStatus.protocol.major}, this UI speaks ${QubiConfig.protocolMajor}`;
        if (root.state === "off") return "engine not running";
        if (root.state === "gaming") return "muted (gaming — CPU only)";
        if (root.state === "warming") return "warming up…";
        if (root.state === "light") return `light tier — ${t?.light?.model ?? ""}`;
        if (root.state === "heavy") return `heavy tier — ${t?.heavy?.model ?? ""}`;
        if (root.state === "claude") return "claude tier active";
        return "idle";
    }
    readonly property string hint: root.protocolMismatch ? "update the engine and the QML together"
        : root.state === "off" ? "is qubi-engine.service running?" : ""

    function _deriveState(s) {
        if (s.gaming) return "gaming";
        if (Object.values(s.tiers).some(x => x.starting)) return "warming";
        if (s.tiers.claude.running) return "claude";
        if (s.tiers.heavy.running) return "heavy";
        return s.tiers.light.ready ? "light" : "idle";
    }

    Socket {
        id: sock
        path: QubiConfig.socketPath
        parser: SplitParser {
            onRead: line => {
                let obj;
                try {
                    obj = JSON.parse(line.trim());
                } catch (e) {
                    return;
                }
                if (obj.result) {
                    root.lastStatus = obj.result;
                    root.state = root._deriveState(obj.result);
                }
            }
        }
        onConnectionStateChanged: if (!sock.connected)
            root.state = "off"
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sock.connected) {
                // Bare `sock.connected = true` alone was confirmed live to
                // NOT actually retry -- same real pattern GooseAcpSession
                // .qml's retryConnect() already had to work around:
                // explicitly re-assigning false first is what actually
                // makes Quickshell's Socket attempt a fresh connection.
                sock.connected = false;
                sock.connected = true;
                return;
            }
            sock.write(JSON.stringify({jsonrpc: "2.0", id: 1, method: "qubi/status", params: {}}) + "\n");
            sock.flush();
        }
    }
}
