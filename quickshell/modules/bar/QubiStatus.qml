import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"

// Engine health at a glance -- own standalone qubi/status poll (NOT
// GooseAcpSession, which creates a real chat session on start()).
// Ultraviolet has no green/orange, so color only conveys the coarse
// off/attention/active tier; exact state lives in the tooltip, same
// split Battery.qml uses (shape = rough tier, tooltip = exact %).
BarIcon {
    id: root

    property string _state: "off"  // off|gaming|warming|idle|light|heavy|claude
    property var _lastStatus: null

    glyph: "Q"
    glyphColorOverride: root._state === "warming" ? Theme.color.accentPink : (root._state === "off" || root._state === "gaming") ? Theme.color.moduleDisabledFg : root._state === "idle" ? Theme.color.rightModuleFg : Theme.color.accentPurple

    CriticalBlink on opacity {
        running: root._state === "warming"
    }

    tooltipTitle: "QUBI"
    tooltipBody: {
        const t = root._lastStatus?.tiers;
        if (root._state === "off") return "engine not running";
        if (root._state === "gaming") return "muted (gaming — CPU only)";
        if (root._state === "warming") return "warming up…";
        if (root._state === "light") return `light tier — ${t?.light?.model ?? ""}`;
        if (root._state === "heavy") return `heavy tier — ${t?.heavy?.model ?? ""}`;
        if (root._state === "claude") return "claude tier active";
        return "idle";
    }
    tooltipMuted: root._state === "off" ? "is qubi-engine.service running?" : ""

    function _deriveState(s) {
        if (s.gaming) return "gaming";
        if (Object.values(s.tiers).some(x => x.starting)) return "warming";
        if (s.tiers.claude.running) return "claude";
        if (s.tiers.heavy.running) return "heavy";
        return s.tiers.light.ready ? "light" : "idle";
    }

    Socket {
        id: sock
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/qubi/engine.sock"
        parser: SplitParser {
            onRead: line => {
                let obj;
                try {
                    obj = JSON.parse(line.trim());
                } catch (e) {
                    return;
                }
                if (obj.result) {
                    root._lastStatus = obj.result;
                    root._state = root._deriveState(obj.result);
                }
            }
        }
        onConnectionStateChanged: if (!sock.connected)
            root._state = "off"
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
