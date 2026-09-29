import QtQuick
import Quickshell.Io
import "../../../theme"
import "../../../services"
import "../../common"
import ".."

// Live system monitor built on SystemStats' shared polling.
// `active` (visible section) acquires SystemStats' detail tier only while
// shown; the base tier is kept alive by the wallpaper regardless.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property bool active: true

    onActiveChanged: {
        if (root.active)
            SystemStats.acquireDetail();
        else
            SystemStats.releaseDetail();
    }
    Component.onCompleted: {
        if (root.active)
            SystemStats.acquireDetail();
    }
    Component.onDestruction: {
        if (root.active)
            SystemStats.releaseDetail();
    }

    // Forces a dependency on SystemStats.histSeq; in-place array mutation
    // alone fires no change signal.
    readonly property int _histTick: SystemStats.histSeq

    function _series(buf) {
        root._histTick;
        const out = [];
        for (let i = 0; i < SystemStats.histFill; i++)
            out.push(SystemStats.histAt(buf, i));
        return out;
    }

    // === GPU (eGPU dock state) ===
    // Polled here rather than in SystemStats: the only GPU worth reading is
    // the eGPU (AMD gpu_busy_percent), absent when undocked.
    property string gpuState: "unknown"
    property real gpuBusyPercent: -1

    Timer {
        interval: 3000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: gpuProc.running = true
    }
    Process {
        id: gpuProc
        command: ["bash", "-lc", [
            "cat /run/ai-workstation/state.json 2>/dev/null || echo '{}'",
            "echo '###SEP###'",
            "for c in /sys/class/drm/card*/device/gpu_busy_percent; do [ -f \"$c\" ] && cat \"$c\"; done"
        ].join("; ")]
        stdout: StdioCollector {
            id: gpuOut
            onStreamFinished: {
                const parts = gpuOut.text.split("###SEP###");
                try {
                    root.gpuState = (JSON.parse((parts[0] ?? "{}").trim())).state ?? "unknown";
                } catch (e) {
                    root.gpuState = "unknown";
                }
                const busy = parseInt((parts[1] ?? "").trim(), 10);
                root.gpuBusyPercent = isNaN(busy) ? -1 : busy;
            }
        }
    }

    // === Processes ===
    // `ps`, not `top`: `comm` has no spaces, so a whitespace split is exact.
    // %CPU is a lifetime average, fine for spotting hogs.
    property var processes: []
    property string sortKey: "cpu"
    property bool sortDesc: true

    readonly property var sortedProcesses: {
        const key = root.sortKey;
        const mul = root.sortDesc ? -1 : 1;
        const list = root.processes.slice();
        list.sort((a, b) => {
            const av = key === "pid" ? a.pid : key === "comm" ? a.comm : key === "mem" ? a.mem : a.cpu;
            const bv = key === "pid" ? b.pid : key === "comm" ? b.comm : key === "mem" ? b.mem : b.cpu;
            if (typeof av === "string")
                return mul * av.localeCompare(bv);
            return mul * (av - bv);
        });
        return list;
    }

    function sortBy(key) {
        if (root.sortKey === key)
            root.sortDesc = !root.sortDesc;
        else {
            root.sortKey = key;
            root.sortDesc = true;
        }
    }

    Timer {
        interval: 2000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: psProc.running = true
    }
    Process {
        id: psProc
        command: ["ps", "-eo", "pid,user,%cpu,%mem,comm", "--no-headers", "--sort=-%cpu"]
        stdout: StdioCollector {
            id: psOut
            onStreamFinished: {
                const lines = psOut.text.split("\n");
                const procs = [];
                for (const raw of lines) {
                    const line = raw.trim();
                    if (line.length === 0)
                        continue;
                    const cols = line.split(/\s+/);
                    if (cols.length < 5)
                        continue;
                    procs.push({
                        pid: parseInt(cols[0], 10),
                        user: cols[1],
                        cpu: parseFloat(cols[2]) || 0,
                        mem: parseFloat(cols[3]) || 0,
                        comm: cols.slice(4).join(" ")
                    });
                    if (procs.length >= 60)
                        break;
                }
                root.processes = procs;
            }
        }
    }

    // Try an unprivileged SIGTERM first; escalate to pkexec only if denied.
    property int _confirmKillPid: -1
    property int _killJobId: -1
    property int _killPid: -1
    property bool _killEscalate: false

    function requestKill(pid) {
        if (root._confirmKillPid === pid) {
            root._confirmKillPid = -1;
            root._doKill(pid, false);
        } else {
            root._confirmKillPid = pid;
        }
    }

    function _doKill(pid, privileged) {
        root._killPid = pid;
        root._killEscalate = !privileged;
        root._killJobId = JobRunner.run(`Kill PID ${pid}`, ["kill", "-TERM", String(pid)], { privileged });
    }

    Connections {
        target: JobRunner
        function onJobsChanged() {
            if (root._killJobId < 0)
                return;
            const job = JobRunner.jobById(root._killJobId);
            if (!job || job.state === "running")
                return;
            root._killJobId = -1;
            if (job.state === "failed" && root._killEscalate)
                root._doKill(root._killPid, true);
        }
    }

    component Bar: Item {
        id: bar
        required property real value
        required property real max
        property color barColor: Theme.color.accentPurple
        width: parent.width
        height: 8

        Rectangle {
            anchors.fill: parent
            radius: 3
            color: ThemeDefaults.alpha(Theme.base16.base02, 0.5)
        }
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * Math.min(1, bar.max > 0 ? bar.value / bar.max : 0)
            radius: 3
            color: bar.barColor

            Behavior on width { NumberAnimation { duration: 200 } }
        }
    }

    component SectionLabel: Text {
        font.bold: true
        font.pixelSize: 14
        color: Theme.color.fg
        font.family: Theme.font.family
    }

    component SmallLabel: Text {
        color: Theme.color.launcherPlaceholderFg
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
    }

    Column {
        id: column
        width: parent.width
        spacing: 16

        Text {
            text: "Monitor"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
            font.family: Theme.font.family
        }

        // === CPU ===
        Column {
            width: parent.width
            spacing: 4

            SectionLabel { text: "CPU" }
            Row {
                width: parent.width
                SmallLabel { text: `${SystemStats.cpuPercent.toFixed(1)}%  ·  load ${SystemStats.load1.toFixed(2)} / ${SystemStats.cpuCount}` }
                Item { width: parent.width - 260; height: 1 }
                SmallLabel { visible: SystemStats.tempC > 0; text: `${SystemStats.tempC.toFixed(0)}°C` }
                SmallLabel { visible: SystemStats.fanRpm >= 0; text: `  ${SystemStats.fanRpm} RPM` }
            }
            HistoryGraph {
                width: parent.width
                series: [{ values: root._series(SystemStats.histCpu), color: Theme.color.accentPurple, fill: true }]
                repaintTick: root._histTick
            }
            Grid {
                width: parent.width
                columns: 8
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: SystemStats.cpuPerCore
                    delegate: Column {
                        required property real modelData
                        required property int index
                        width: (column.width - 28) / 8
                        spacing: 1
                        SmallLabel { text: `C${index}`; font.pixelSize: 9 }
                        Bar { width: parent.width; value: modelData; max: 100 }
                    }
                }
            }
        }

        // === Memory ===
        Column {
            width: parent.width
            spacing: 4

            SectionLabel { text: "Memory" }
            SmallLabel {
                text: `${(SystemStats.memUsedMiB / 1024).toFixed(1)} / ${(SystemStats.memTotalMiB / 1024).toFixed(1)} GiB` +
                      (SystemStats.swapTotalMiB > 0 ? `  ·  swap ${(SystemStats.swapUsedMiB / 1024).toFixed(1)} / ${(SystemStats.swapTotalMiB / 1024).toFixed(1)} GiB` : "")
            }
            HistoryGraph {
                width: parent.width
                maxValue: 100
                series: [
                    { values: root._series(SystemStats.histMem), color: Theme.color.accentPink, fill: true }
                ]
                repaintTick: root._histTick
            }
        }

        // === Network ===
        Column {
            width: parent.width
            spacing: 4

            SectionLabel { text: "Network" }
            SmallLabel { text: `↓ ${(SystemStats.netRxBps / 1e6).toFixed(2)} MB/s   ↑ ${(SystemStats.netTxBps / 1e6).toFixed(2)} MB/s` }
            HistoryGraph {
                width: parent.width
                maxValue: 0 // autoscale -- network throughput has no fixed ceiling
                series: [
                    { values: root._series(SystemStats.histNetRx), color: Theme.color.accentPurple, fill: false },
                    { values: root._series(SystemStats.histNetTx), color: Theme.color.accentPink, fill: false }
                ]
                repaintTick: root._histTick
            }
        }

        // === Disk ===
        Column {
            width: parent.width
            spacing: 4

            SectionLabel { text: "Disk" }
            SmallLabel { text: `↓ ${(SystemStats.diskReadBps / 1e6).toFixed(2)} MB/s   ↑ ${(SystemStats.diskWriteBps / 1e6).toFixed(2)} MB/s   ·   / ${(SystemStats.rootUsedFrac * 100).toFixed(0)}% used` }
            HistoryGraph {
                width: parent.width
                maxValue: 0
                series: [
                    { values: root._series(SystemStats.histDiskR), color: Theme.color.accentPurple, fill: false },
                    { values: root._series(SystemStats.histDiskW), color: Theme.color.accentPink, fill: false }
                ]
                repaintTick: root._histTick
            }
            Bar { width: parent.width; value: SystemStats.rootUsedFrac * 100; max: 100 }
        }

        // === Pressure (PSI) ===
        Column {
            width: parent.width
            spacing: 4
            visible: SystemStats.psiCpuSome10 >= 0

            SectionLabel { text: "Pressure" }
            Row {
                width: parent.width
                SmallLabel { width: parent.width / 3; text: `CPU ${SystemStats.psiCpuSome10.toFixed(1)}%` }
                SmallLabel { width: parent.width / 3; text: `IO ${SystemStats.psiIoSome10.toFixed(1)}%` }
                SmallLabel { width: parent.width / 3; text: `MEM ${SystemStats.psiMemSome10.toFixed(1)}%` }
            }
            Row {
                width: parent.width
                spacing: 4
                Bar { width: parent.width / 3 - 3; value: SystemStats.psiCpuSome10; max: 100; barColor: Theme.color.accentPurple }
                Bar { width: parent.width / 3 - 3; value: SystemStats.psiIoSome10; max: 100; barColor: Theme.color.accentPink }
                Bar { width: parent.width / 3 - 3; value: SystemStats.psiMemSome10; max: 100; barColor: Theme.color.accentPurple }
            }
        }

        // === GPU ===
        Column {
            width: parent.width
            spacing: 4

            SectionLabel { text: "GPU (eGPU)" }
            SmallLabel {
                text: root.gpuState !== "docked"
                    ? "eGPU not docked"
                    : (root.gpuBusyPercent >= 0 ? `${root.gpuBusyPercent}% busy` : "docked, no busy-percent sensor found")
            }
            Bar {
                visible: root.gpuState === "docked" && root.gpuBusyPercent >= 0
                width: parent.width
                value: root.gpuBusyPercent
                max: 100
                barColor: Theme.color.accentPink
            }
        }

        // === Processes ===
        Column {
            width: parent.width
            spacing: 4

            SectionLabel { text: "Processes" }

            component HeaderCell: Text {
                required property string label
                required property string key
                text: root.sortKey === key ? (label + (root.sortDesc ? " ▾" : " ▴")) : label
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                font.bold: true
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortBy(parent.key)
                }
            }

            Row {
                width: parent.width
                spacing: 8
                HeaderCell { width: 55; label: "PID"; key: "pid" }
                HeaderCell { width: 55; label: "CPU%"; key: "cpu" }
                HeaderCell { width: 55; label: "MEM%"; key: "mem" }
                HeaderCell { width: parent.width - 55 * 3 - 24 - 60; label: "COMMAND"; key: "comm" }
                Item { width: 60; height: 1 }
            }

            ListView {
                width: parent.width
                height: Math.min(400, root.sortedProcesses.length * 22)
                clip: true
                model: root.sortedProcesses

                delegate: Row {
                    id: procRow
                    required property var modelData
                    width: ListView.view.width
                    height: 22
                    spacing: 8

                    Text { width: 55; text: procRow.modelData.pid; color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    Text { width: 55; text: procRow.modelData.cpu.toFixed(1); color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    Text { width: 55; text: procRow.modelData.mem.toFixed(1); color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    Text {
                        width: procRow.width - 55 * 3 - 24 - 60
                        elide: Text.ElideRight
                        text: procRow.modelData.comm
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    Rectangle {
                        width: 60
                        height: 18
                        radius: 4
                        color: root._confirmKillPid === procRow.modelData.pid ? Theme.color.critical : "transparent"
                        border.width: 1
                        border.color: Theme.color.critical

                        Text {
                            anchors.centerIn: parent
                            text: root._confirmKillPid === procRow.modelData.pid ? "confirm" : "kill"
                            color: root._confirmKillPid === procRow.modelData.pid ? Theme.color.launcherTabActiveFg : Theme.color.critical
                            font.family: Theme.font.family
                            font.pixelSize: 9
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestKill(procRow.modelData.pid)
                        }
                    }
                }
            }
        }
    }
}
