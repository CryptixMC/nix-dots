pragma Singleton
import QtQuick
import Quickshell.Io

// Runs long-running or privileged launcher commands in the background;
// privileged ones get `pkexec` prefixed so the session's polkit agent handles auth.
// Process objects are created per job with createObject (an Instantiator would
// restart in-flight processes on every model change) and kept in the plain `_procs`
// map, outside the reactive `jobs` array.
Item {
    id: root

    readonly property int maxOutputLines: 2000
    readonly property int maxJobHistory: 50

    property var jobs: []
    property int _jobSeq: 0
    readonly property int runningCount: root.jobs.filter(j => j.state === "running").length

    property var _procs: ({})
    property var _cancelRequested: ({})

    // opts: { privileged: bool, cwd: string }
    function run(label, argv, opts) {
        opts = opts ?? {};
        const id = ++root._jobSeq;
        const finalArgv = opts.privileged ? ["pkexec", ...argv] : argv;

        const job = {
            id: id,
            label: label,
            argv: argv,
            privileged: !!opts.privileged,
            state: "running",
            exitCode: null,
            startedAt: Date.now(),
            output: []
        };
        root.jobs = [job, ...root.jobs].slice(0, root.maxJobHistory);

        const proc = jobProcComponent.createObject(root, {
            command: finalArgv,
            jobId: id,
            workingDirectory: opts.cwd ?? ""
        });
        root._procs[id] = proc;
        proc.running = true;
        return id;
    }

    function cancel(id) {
        const p = root._procs[id];
        if (p && p.running) {
            root._cancelRequested[id] = true;
            p.signal(15); // SIGTERM; no SIGKILL escalation yet
        }
    }

    function jobById(id) {
        return root.jobs.find(j => j.id === id) ?? null;
    }

    // Reassigns the whole `jobs` array to notify bindings. Chatty commands
    // re-serialize every job per line; fine at admin-command volume.
    function _appendOutput(id, line) {
        root.jobs = root.jobs.map(j => {
            if (j.id !== id)
                return j;
            const out = j.output.length >= root.maxOutputLines ? j.output.slice(1) : j.output;
            return Object.assign({}, j, {
                output: [...out, line]
            });
        });
    }

    // Idempotent: onExited and onErrorOccurred can both fire for a failed launch.
    function _finishJob(id, exitCode) {
        const existing = root.jobById(id);
        if (!existing || existing.state !== "running")
            return;
        const wasCancelled = !!root._cancelRequested[id];
        root.jobs = root.jobs.map(j => j.id === id ? Object.assign({}, j, {
            state: wasCancelled ? "cancelled" : (exitCode === 0 ? "ok" : "failed"),
            exitCode: exitCode
        }) : j);
        delete root._procs[id];
        delete root._cancelRequested[id];
    }

    Component {
        id: jobProcComponent

        Process {
            id: proc
            required property int jobId

            stdout: SplitParser {
                onRead: line => root._appendOutput(proc.jobId, line)
            }
            stderr: SplitParser {
                onRead: line => root._appendOutput(proc.jobId, line)
            }

            onExited: (exitCode, exitStatus) => root._finishJob(proc.jobId, exitCode)

            // Process exposes errorOccurred as a method, not a signal, so the
            // `onX: handler` form fails; override it as a function with the exact name.
            function onErrorOccurred(error) {
                root._finishJob(proc.jobId, -1);
            }
        }
    }
}
