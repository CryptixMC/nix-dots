import QtQuick
import Quickshell.Io
import "../../theme"
import Qubi

// Qubi engine health in the bar; logic lives in Qubi's QubiStatusModel.
// Color only conveys the coarse tier; exact state is in the tooltip.
//
// The tooltip also shows Claude subscription usage, which is host-local
// (see modules/home-manager/apps/claude-usage.nix), not part of Qubi.
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

    glyphColorOverride: (model.state === "warming" || model.protocolMismatch) ? Theme.color.accentPink : (model.state === "off" || model.state === "gaming") ? Theme.color.moduleDisabledFg : model.state === "idle" ? Theme.color.rightModuleFg : Theme.color.accentPurple

    glyphComponent: Component {
        QubiGlyph {
            width: Theme.font.sizeBase
            height: Theme.font.sizeBase
            nodeColor: root.glyphColorOverride
        }
    }

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

    // The usage endpoint is undocumented and rate-limits hard (429 with
    // 1100+s retry-after); don't shorten the 15 min interval.
    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: usageProc.running = true
    }
}
