pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower

// Shared live system-metrics singleton. Built for the ultraviolet-v2
// orbital wallpaper (quickshell/modules/wallpaper/scenes/Orbital.qml),
// which turns these into HUD readouts, but nothing here is
// wallpaper-specific — any consumer can bind these properties.
//
// FileView + Timer, not a batched `bash -lc` (contrast
// modules/launcher/SystemMonitor.qml, which argues for one combined
// `top -bn1` call): that reasoning rests on the poller only running while
// its panel is open, and on `top` doing its own internal sampling. This
// singleton runs 24/7 on every monitor and its entire job is to display a
// CPU number — a `bash -lc` fork+exec would cost ~1-3ms of CPU every
// tick, forever, which would itself show up in the number being
// rendered. /proc and /sys reads cost microseconds. FileView's
// `watchChanges` is NOT used here — /proc and thermal sysfs don't fire
// inotify on read (see Temperature.qml's comment) — so this polls via
// Timer + reload(), same as Temperature.qml.
//
// Polling is refcounted (acquire()/release()) so a theme that never loads
// the scene, a bar-less session, or every monitor once fullscreen pauses
// it all pay exactly zero. Callers that want polling to track a
// "shouldAnimate"-style condition (not just component lifetime) should
// acquire()/release() on that condition changing, not just on
// Component.onCompleted/onDestruction alone.
Item {
    id: root

    property int consumerCount: 0
    readonly property bool polling: consumerCount > 0

    function acquire() {
        root.consumerCount++;
    }
    function release() {
        root.consumerCount = Math.max(0, root.consumerCount - 1);
    }

    // Second, opt-in refcount for the more expensive/niche metrics below
    // (per-core temps, fan, PSI, disk I/O) -- gated separately from
    // `polling` so the wallpaper's 24/7 `acquire()` never pays for data
    // only a genuinely detail-hungry consumer (SystemMonitor.qml) wants.
    // Same acquire-on-condition discipline as `polling` applies here too.
    property int detailCount: 0
    readonly property bool pollingDetail: detailCount > 0

    function acquireDetail() {
        root.detailCount++;
    }
    function releaseDetail() {
        root.detailCount = Math.max(0, root.detailCount - 1);
    }

    // === CPU ===
    property real cpuPercent: 0
    property real _lastTotal: -1
    property real _lastIdle: 0

    // Per-core percentages, index-aligned to /proc/stat's own cpuN
    // numbering. Consumers (e.g. the NeuralNet wallpaper scene) must size
    // themselves from cpuPerCore.length, not cpuCount below — cpuCount
    // comes from a separate `nproc` process and can drift from what
    // /proc/stat actually reports in a cgroup/cpuset-restricted container.
    property var cpuPerCore: []
    property var _perCoreLast: [] // [{lastTotal, lastIdle}], index-aligned

    function _parseCpuLine(text) {
        // 8192 chars comfortably covers the aggregate "cpu " line plus
        // several dozen "cpuN ..." lines before /proc/stat's variable-
        // length intr/ctxt tail (one counter per IRQ) even starts —
        // avoids splitting that whole tail just to read the CPU lines.
        const lines = text.substring(0, 8192).split("\n");
        const f = lines[0].trim().split(/\s+/).slice(1).map(Number);
        if (f.length < 4)
            return;
        const idleAll = f[3] + (f[4] ?? 0);
        const total = f.reduce((a, b) => a + b, 0);
        if (root._lastTotal < 0) {
            // First sample has no delta to compare against — emit 0
            // rather than a bogus 100% from (total-0)/(idle-0).
            root._lastTotal = total;
            root._lastIdle = idleAll;
            root.cpuPercent = 0;
        } else {
            const dTotal = total - root._lastTotal;
            const dIdle = idleAll - root._lastIdle;
            root.cpuPercent = dTotal > 0 ? 100 * (1 - dIdle / dTotal) : 0;
            root._lastTotal = total;
            root._lastIdle = idleAll;
        }

        // Per-core lines are contiguous starting at line 1; the first
        // line that doesn't match "cpuN ..." ends the block.
        const cores = [];
        for (let i = 1; i < lines.length; i++) {
            const m = lines[i].match(/^cpu(\d+)\s+(.*)/);
            if (!m)
                break;
            const idx = parseInt(m[1]);
            const cf = m[2].trim().split(/\s+/).map(Number);
            if (cf.length < 4)
                continue;
            const cIdle = cf[3] + (cf[4] ?? 0);
            const cTotal = cf.reduce((a, b) => a + b, 0);
            const base = root._perCoreLast[idx];
            if (!base) {
                root._perCoreLast[idx] = { lastTotal: cTotal, lastIdle: cIdle };
                cores[idx] = 0;
                continue;
            }
            const dT = cTotal - base.lastTotal;
            const dI = cIdle - base.lastIdle;
            cores[idx] = dT > 0 ? 100 * (1 - dI / dT) : 0;
            base.lastTotal = cTotal;
            base.lastIdle = cIdle;
        }
        // Reassigned wholesale (never mutated in place) so bindings that
        // read cpuPerCore actually re-evaluate.
        root.cpuPerCore = Array.from({ length: cores.length }, (_, i) => cores[i] ?? 0);
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: root._parseCpuLine(text())
    }

    // === Memory ===
    property real memTotalMiB: 0
    property real memAvailMiB: 0
    readonly property real memUsedMiB: Math.max(0, memTotalMiB - memAvailMiB)
    readonly property real memUsedFrac: memTotalMiB > 0 ? memUsedMiB / memTotalMiB : 0
    // Swap -- same file already being read every tick, so these are free.
    property real swapTotalMiB: 0
    property real swapFreeMiB: 0
    readonly property real swapUsedMiB: Math.max(0, swapTotalMiB - swapFreeMiB)

    function _parseMeminfo(text) {
        function field(name) {
            const i = text.indexOf(name + ":");
            if (i < 0)
                return 0;
            const rest = text.substring(i + name.length + 1, i + name.length + 32);
            return parseFloat(rest) || 0; // kB
        }
        root.memTotalMiB = field("MemTotal") / 1024;
        root.memAvailMiB = field("MemAvailable") / 1024;
        root.swapTotalMiB = field("SwapTotal") / 1024;
        root.swapFreeMiB = field("SwapFree") / 1024;
    }

    FileView {
        id: meminfoFile
        path: "/proc/meminfo"
        onLoaded: root._parseMeminfo(text())
    }

    // === Network throughput + link state ===
    // Primary source is Quickshell.Networking's connected device — this
    // gives netOnline for free with zero polling and never enumerates
    // veth/docker/tailscale noise (Network.qml's duck-typed idiom, reused
    // verbatim). Byte-counter reads are the one thing Networking has no
    // API for (Network.qml's own comment documents this gap) — that part
    // is polled from sysfs directly.
    readonly property var _wifiDevices: Networking.devices.values.filter(d => d.networks !== undefined)
    readonly property var _connected: Networking.devices.values.find(d => d.connected) ?? null
    readonly property bool netOnline: root._connected !== null
    readonly property string netIface: root._connected?.name ?? root._fallbackIface

    property string _fallbackIface: ""
    property real netRxBps: 0
    property real netTxBps: 0
    property real _lastRx: -1
    property real _lastTx: -1

    // Re-run when Networking's device list changes (e.g. wifi toggled) and
    // nothing is currently connected — last-resort default-route lookup.
    Process {
        id: routeProc
        command: ["sh", "-c", "ip route show default 2>/dev/null | awk '{print $5; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const iface = text.trim();
                if (iface.length > 0)
                    root._fallbackIface = iface;
            }
        }
    }

    Connections {
        target: Networking.devices
        function onValuesChanged() {
            if (root._connected === null)
                routeProc.running = true;
        }
    }

    // Path is reassigned whenever the interface changes, so the delta
    // baseline must reset — otherwise the counter jump from interface A's
    // accumulated bytes to interface B's renders as a fake spike.
    onNetIfaceChanged: {
        root._lastRx = -1;
        root._lastTx = -1;
    }

    function _parseCounter(text) {
        return parseFloat(text) || 0;
    }

    FileView {
        id: netRxFile
        path: root.netIface ? `/sys/class/net/${root.netIface}/statistics/rx_bytes` : ""
        onLoaded: {
            const v = root._parseCounter(text());
            root.netRxBps = root._lastRx < 0 ? 0 : Math.max(0, v - root._lastRx);
            root._lastRx = v;
        }
    }
    FileView {
        id: netTxFile
        path: root.netIface ? `/sys/class/net/${root.netIface}/statistics/tx_bytes` : ""
        onLoaded: {
            const v = root._parseCounter(text());
            root.netTxBps = root._lastTx < 0 ? 0 : Math.max(0, v - root._lastTx);
            root._lastTx = v;
        }
    }

    // === Disk I/O (detail tier) ===
    // /proc/diskstats sectors (always 512 bytes regardless of the device's
    // real block size -- a kernel-ABI constant, not this disk's actual
    // sector size) for whole physical devices only. The name filter
    // excludes partitions (nvme0n1p1 etc, which would double-count against
    // the whole-device line) and zram (RAM-backed swap -- its "disk" I/O
    // is memory bandwidth, not storage, and would inflate both counters
    // with numbers that don't mean what this graph implies).
    property real diskReadBps: 0
    property real diskWriteBps: 0
    property real _lastDiskRead: -1
    property real _lastDiskWrite: -1

    function _parseDiskstats(text) {
        let readSectors = 0;
        let writeSectors = 0;
        for (const line of text.split("\n")) {
            const f = line.trim().split(/\s+/);
            if (f.length < 10)
                continue;
            const name = f[2];
            if (!/^(nvme\d+n\d+|sd[a-z]+|mmcblk\d+)$/.test(name))
                continue;
            readSectors += parseFloat(f[5]) || 0;
            writeSectors += parseFloat(f[9]) || 0;
        }
        const readBytes = readSectors * 512;
        const writeBytes = writeSectors * 512;
        root.diskReadBps = root._lastDiskRead < 0 ? 0 : Math.max(0, readBytes - root._lastDiskRead);
        root.diskWriteBps = root._lastDiskWrite < 0 ? 0 : Math.max(0, writeBytes - root._lastDiskWrite);
        root._lastDiskRead = readBytes;
        root._lastDiskWrite = writeBytes;
    }

    FileView {
        id: diskstatsFile
        path: "/proc/diskstats"
        onLoaded: root._parseDiskstats(text())
    }

    // === PSI (Pressure Stall Information, detail tier) ===
    // Plain readable files, no subprocess needed. `full` isn't meaningful
    // for `cpu` (a thread can always yield the CPU to another; the kernel
    // doesn't report it) or `some`-only situations for the same reason
    // this repo's own experience with these files agrees with the kernel
    // docs on -- only `some` is read for cpu, both `some`/`full` for io
    // and memory.
    property real psiCpuSome10: 0
    property real psiIoSome10: 0
    property real psiIoFull10: 0
    property real psiMemSome10: 0
    property real psiMemFull10: 0

    function _parsePsiAvg10(text, kind) {
        const re = new RegExp(`^${kind}.*?avg10=([\\d.]+)`, "m");
        const m = text.match(re);
        return m ? parseFloat(m[1]) || 0 : 0;
    }

    FileView {
        id: psiCpuFile
        path: "/proc/pressure/cpu"
        onLoaded: root.psiCpuSome10 = root._parsePsiAvg10(text(), "some")
    }
    FileView {
        id: psiIoFile
        path: "/proc/pressure/io"
        onLoaded: {
            const t = text();
            root.psiIoSome10 = root._parsePsiAvg10(t, "some");
            root.psiIoFull10 = root._parsePsiAvg10(t, "full");
        }
    }
    FileView {
        id: psiMemFile
        path: "/proc/pressure/memory"
        onLoaded: {
            const t = text();
            root.psiMemSome10 = root._parsePsiAvg10(t, "some");
            root.psiMemFull10 = root._parsePsiAvg10(t, "full");
        }
    }

    // === Per-core temperature + fan RPM (detail tier) ===
    // Sparse, non-contiguous temp*_input indices on this machine's
    // coretemp (temp1=package, then temp2,6,10,14,18..25 for individual
    // cores) rule out any loop assuming temp1..tempN contiguous -- indices
    // are discovered from each temp*_label file's own content instead.
    // hwmon numbering itself isn't stable across reboots either (same
    // caveat Temperature.qml's own comment documents), so this re-runs
    // discovery every time detail polling (re)starts rather than caching
    // it once for the process lifetime.
    property var coreTemps: [] // [{label, c}]
    property real fanRpm: -1 // -1 = no fan sensor found
    property var _tempSensors: [] // [{path, label}]
    property string _fanPath: ""

    Process {
        id: detailDiscoveryProc
        command: ["sh", "-c", [
            "CORETEMP=$(grep -l coretemp /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1)",
            "if [ -n \"$CORETEMP\" ]; then",
            "  DIR=$(dirname \"$CORETEMP\")",
            "  for f in \"$DIR\"/temp*_label; do",
            "    [ -f \"$f\" ] || continue",
            "    idx=$(basename \"$f\" | sed 's/temp//;s/_label//')",
            "    echo \"TEMP:$DIR/temp${idx}_input:$(cat \"$f\")\"",
            "  done",
            "fi",
            "THINKPAD=$(grep -l thinkpad /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1)",
            "if [ -n \"$THINKPAD\" ]; then",
            "  TDIR=$(dirname \"$THINKPAD\")",
            "  [ -f \"$TDIR/fan1_input\" ] && echo \"FAN:$TDIR/fan1_input\"",
            "fi"
        ].join("\n")]
        stdout: StdioCollector {
            onStreamFinished: {
                const sensors = [];
                let fanPath = "";
                for (const line of text.trim().split("\n").filter(l => l.length > 0)) {
                    const idx = line.indexOf(":");
                    if (idx < 0)
                        continue;
                    const tag = line.slice(0, idx);
                    const rest = line.slice(idx + 1);
                    if (tag === "TEMP") {
                        const sep = rest.indexOf(":");
                        if (sep < 0)
                            continue;
                        sensors.push({
                            path: rest.slice(0, sep),
                            label: rest.slice(sep + 1)
                        });
                    } else if (tag === "FAN") {
                        fanPath = rest;
                    }
                }
                root._tempSensors = sensors;
                root._fanPath = fanPath;
                detailReadProc.running = true;
            }
        }
    }

    Process {
        id: detailReadProc
        command: ["sh", "-c", root._tempSensors.map(s => `echo "T:${s.label}:$(cat ${s.path} 2>/dev/null)"`).concat(root._fanPath ? [`echo "F:$(cat ${root._fanPath} 2>/dev/null)"`] : []).join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const temps = [];
                let fan = -1;
                for (const line of text.trim().split("\n").filter(l => l.length > 0)) {
                    if (line.startsWith("T:")) {
                        const rest = line.slice(2);
                        const sep = rest.indexOf(":");
                        if (sep < 0)
                            continue;
                        const label = rest.slice(0, sep);
                        const milli = parseInt(rest.slice(sep + 1), 10);
                        if (!isNaN(milli))
                            temps.push({
                                label: label,
                                c: milli / 1000
                            });
                    } else if (line.startsWith("F:")) {
                        const rpm = parseInt(line.slice(2), 10);
                        fan = isNaN(rpm) ? -1 : rpm;
                    }
                }
                root.coreTemps = temps;
                root.fanRpm = fan;
            }
        }
    }

    // === Temperature ===
    // hwmon discovery lifted verbatim from Temperature.qml (comments
    // included) rather than reinvented — having Temperature.qml itself
    // consume SystemStats.tempC afterward is a good follow-up but is out
    // of scope for the wallpaper change that introduced this file.
    property string _tempPath: "/sys/class/thermal/thermal_zone6/temp"
    property real tempC: 0
    readonly property bool tempCritical: tempC >= 80

    Process {
        running: true
        command: ["sh", "-c", "grep -l coretemp /sys/class/hwmon/hwmon*/name 2>/dev/null | head -n1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.length > 0)
                    root._tempPath = line.replace(/\/name$/, "") + "/temp1_input";
            }
        }
    }

    FileView {
        id: tempFile
        path: root._tempPath
        onLoaded: root.tempC = (parseInt(text()) || 0) / 1000
    }

    // === Uptime / load / core count ===
    property real uptimeSeconds: 0
    readonly property string uptimeText: {
        const s = Math.max(0, Math.floor(uptimeSeconds));
        const days = Math.floor(s / 86400);
        const hours = Math.floor((s % 86400) / 3600);
        const mins = Math.floor((s % 3600) / 60);
        return `${days}d ${String(hours).padStart(2, "0")}:${String(mins).padStart(2, "0")}`;
    }
    property real load1: 0
    property int cpuCount: 1

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.uptimeSeconds = parseFloat(text()) || 0
    }
    FileView {
        id: loadavgFile
        path: "/proc/loadavg"
        onLoaded: root.load1 = parseFloat(text()) || 0
    }
    Process {
        running: true
        command: ["nproc"]
        stdout: StdioCollector {
            onStreamFinished: root.cpuCount = parseInt(text) || 1
        }
    }

    // === Disk (root filesystem) ===
    property real rootFreeGiB: 0
    property real rootUsedFrac: 0

    Process {
        id: dfProc
        command: ["df", "-B1", "--output=size,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines.length < 2)
                    return;
                const [sizeStr, availStr] = lines[1].trim().split(/\s+/);
                const size = parseFloat(sizeStr) || 0;
                const avail = parseFloat(availStr) || 0;
                root.rootFreeGiB = avail / (1024 * 1024 * 1024);
                root.rootUsedFrac = size > 0 ? Math.max(0, size - avail) / size : 0;
            }
        }
    }

    // === Hostname (static for the process lifetime — one-shot) ===
    property string hostname: "localhost"

    FileView {
        path: "/etc/hostname"
        onLoaded: root.hostname = text().trim()
    }

    // === Battery === (event-driven via UPower, no polling needed)
    readonly property var _battDevice: UPower.displayDevice
    // UPowerDevice.percentage is a 0.0-1.0 fraction, not 0-100 — see
    // Battery.qml's identical comment; normalized once here so no
    // consumer has to remember this.
    readonly property real batteryPercent: (root._battDevice?.percentage ?? 0) * 100
    readonly property bool batteryCharging: root._battDevice?.state === UPowerDeviceState.Charging || root._battDevice?.state === UPowerDeviceState.PendingCharge
    readonly property bool batteryCritical: root.batteryPercent <= 15 && root._battDevice?.state === UPowerDeviceState.Discharging

    // === History ring buffers ===
    // Fixed-length arrays allocated ONCE, written in place via a shared
    // rotating cursor rather than reassigned/shifted every tick -- a dozen
    // independent consumers (bar sparkline, Monitor's graphs, Quick
    // Settings' stats strip) all wanting the same series is the reason
    // this lives here rather than per-consumer: one shared buffer, one
    // shared write cursor, one change notification per tick.
    //
    // In-place mutation of a `var` array does NOT emit a QML change signal
    // on its own (UsageStore.qml documents this exact behavior as a
    // footgun) -- exploited deliberately here: `histSeq` is the only
    // property a consumer binds on to know new data landed (e.g.
    // `HistoryGraph.repaintKey: SystemStats.histSeq`); the buffers
    // themselves are read via histAt() at paint time, never bound to
    // directly.
    readonly property int histLen: 60
    property var histCpu: new Array(60).fill(0)
    property var histMem: new Array(60).fill(0)
    property var histNetRx: new Array(60).fill(0)
    property var histNetTx: new Array(60).fill(0)
    property var histDiskR: new Array(60).fill(0)
    property var histDiskW: new Array(60).fill(0)
    property var histPsiCpu: new Array(60).fill(0)
    property int histHead: 0
    property int histFill: 0 // real samples so far -- readers skip the fake leading zeros
    property int histSeq: 0 // bump this, and only this, to signal "new data"

    // Oldest-to-newest read helper: histAt(buf, 0) is the oldest sample in
    // the window, histAt(buf, histFill - 1) is the most recent.
    function histAt(buf, i) {
        return buf[(root.histHead + 1 + i) % root.histLen];
    }

    // Sampled at the TOP of the fast timer, before that tick's reload()s —
    // FileView.reload() is async, so this uses the PREVIOUS tick's parsed
    // values rather than blocking on fresh ones. That's 1s of lag, invisible
    // on a 60-sample/60s window, and avoids a fourth timer just for this.
    function _sampleHistory() {
        root.histHead = (root.histHead + 1) % root.histLen;
        root.histCpu[root.histHead] = root.cpuPercent;
        root.histMem[root.histHead] = root.memUsedFrac * 100;
        root.histNetRx[root.histHead] = root.netRxBps;
        root.histNetTx[root.histHead] = root.netTxBps;
        if (root.pollingDetail) {
            root.histDiskR[root.histHead] = root.diskReadBps;
            root.histDiskW[root.histHead] = root.diskWriteBps;
            root.histPsiCpu[root.histHead] = root.psiCpuSome10;
        }
        if (root.histFill < root.histLen)
            root.histFill++;
        root.histSeq++;
    }

    // Detail-tier sensor discovery must re-run every time detail polling
    // (re)starts, not just once for the process lifetime -- hwmon
    // numbering isn't stable across reboots/hotplugs (same caveat
    // Temperature.qml documents), so a stale cached path from a previous
    // session could silently point at the wrong sensor.
    onPollingDetailChanged: {
        if (root.pollingDetail)
            detailDiscoveryProc.running = true;
    }

    // === Timers ===
    // Fast tier: CPU, memory and net throughput all want short intervals
    // for their deltas to mean anything.
    Timer {
        interval: 1000
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._sampleHistory();
            statFile.reload();
            meminfoFile.reload();
            netRxFile.reload();
            netTxFile.reload();
        }
    }
    // Slow tier: temperature, uptime, load average change slowly enough
    // that 5s is indistinguishable from 1s on a wallpaper.
    Timer {
        interval: 5000
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            tempFile.reload();
            uptimeFile.reload();
            loadavgFile.reload();
        }
    }
    // Very slow tier: disk usage barely moves; a `df` fork+exec is the
    // one genuine subprocess in the polling set (there's no /proc/sys
    // equivalent), so it's kept to once every 5 minutes.
    Timer {
        interval: 300000
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: dfProc.running = true
    }

    // === Detail-tier timers ===
    // 1s: disk I/O + PSI, same cadence as the fast tier above since their
    // deltas/averages are only meaningful at short intervals.
    Timer {
        interval: 1000
        running: root.pollingDetail
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            diskstatsFile.reload();
            psiCpuFile.reload();
            psiIoFile.reload();
            psiMemFile.reload();
        }
    }
    // 5s: per-core temps + fan RPM. No triggeredOnStart -- the discovery
    // Process (kicked off by onPollingDetailChanged above) already fires
    // the first real read itself once sensor paths are known; starting
    // this timer immediately would instead fire one wasted `sh -c ""` read
    // against an empty, not-yet-discovered sensor list.
    Timer {
        interval: 5000
        running: root.pollingDetail
        repeat: true
        onTriggered: {
            if (root._tempSensors.length > 0 || root._fanPath.length > 0)
                detailReadProc.running = true;
        }
    }
}
