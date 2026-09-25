import QtQuick
import Quickshell.Io
import "../../theme"
import Qubi

// Qubi engine health in the bar. All the logic (socket, state derivation,
// tooltip strings) is Qubi's own QubiStatusModel; this is only how this
// shell draws it. Ultraviolet has no green/orange, so color only conveys
// the coarse off/attention/active tier; exact state lives in the tooltip,
// same split Battery.qml uses (shape = rough tier, tooltip = exact %).
//
// The tooltip also carries this account's Claude subscription usage (5h
// rolling window + weekly), unrelated to Qubi's own engine tiers -- it's
// nix-dots/host-local (reads ~/.claude/.credentials.json), not part of
// Qubi's protocol, so it's bolted on here rather than into QubiStatusModel.
// See modules/home-manager/apps/claude-usage.nix for the actual fetch.
BarIcon {
    id: root

    QubiStatusModel {
        id: model
    }

    property var usageData: ({ ok: false })

    function formatResetIn(iso) {
        if (!iso)
            return "";
        const ms = new Date(iso).getTime() - Date.now();
        if (isNaN(ms) || ms <= 0)
            return "";
        const h = Math.floor(ms / 3600000);
        const m = Math.floor((ms % 3600000) / 60000);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    readonly property string usageLine: {
        if (!root.usageData.ok)
            return root.usageData.error ? `claude usage: ${root.usageData.error}` : "";
        const fh = root.usageData.fiveHourPct.toFixed(0);
        const wk = root.usageData.sevenDayPct.toFixed(0);
        const fhReset = root.formatResetIn(root.usageData.fiveHourResetsAt);
        const wkReset = root.formatResetIn(root.usageData.sevenDayResetsAt);
        return `claude: ${fh}%/5h${fhReset ? ` (${fhReset})` : ""} · ${wk}%/wk${wkReset ? ` (${wkReset})` : ""}`;
    }

    glyph: "Q"
    glyphColorOverride: (model.state === "warming" || model.protocolMismatch) ? Theme.color.accentPink : (model.state === "off" || model.state === "gaming") ? Theme.color.moduleDisabledFg : model.state === "idle" ? Theme.color.rightModuleFg : Theme.color.accentPurple

    CriticalBlink on opacity {
        running: model.state === "warming"
    }

    tooltipTitle: model.title
    tooltipBody: model.body
    tooltipMuted: [model.hint, root.usageLine].filter(s => s.length > 0).join("\n")

    Process {
        id: usageProc
        command: ["claude-usage-check"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.usageData = JSON.parse(text);
                } catch (e) {
                    root.usageData = { ok: false, error: "bad output" };
                }
            }
        }
    }

    // Confirmed live against the real endpoint: a handful of manual test
    // calls in one sitting was enough to earn a 429 with an 1100+s
    // retry-after. 15 minutes is a deliberately conservative cadence for
    // an undocumented, aggressively-limited endpoint -- do not shorten
    // this without re-confirming the actual limit.
    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: usageProc.running = true
    }
}
