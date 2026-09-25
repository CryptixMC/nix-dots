pragma Singleton
import QtQuick
import Quickshell.Io

// Replaces SystemState.runInTerminal() everywhere -- every long-running or
// privileged shell command in the launcher (update buttons, service
// restarts, maintenance cleanup, and every widget/tab built on top of this)
// routes through here instead of spawning a Ghostty window. Non-privileged
// commands just run; privileged ones get `pkexec` prefixed, which hands the
// authorization request to whichever polkit agent is registered for the
// session -- PolkitAgentService/AuthPromptWindow, once that's wired in and
// confirmed live (see PolkitAgentService.qml's header). No extra plumbing
// needed here for that hookup: pkexec talks to polkit, not to us directly.
//
// Process objects are created dynamically per job via Component.createObject
// rather than a static declaration (this repo's Instantiator convention
// elsewhere assumes a model whose *set* changes together, e.g. one delegate
// per discovered theme -- recreating it on every job-state change would
// destroy and restart in-flight processes, which is exactly wrong for a job
// queue). Live Process objects are kept OUTSIDE the reactive `jobs` array
// (in a plain JS map, `_procs`) so cancel() can reach them without that
// lookup itself triggering a re-render.
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
            p.signal(15); // SIGTERM -- escalate to 9 (SIGKILL) only via a
            // deliberate second call if a job ever needs it; not exposed yet.
        }
    }

    function jobById(id) {
        return root.jobs.find(j => j.id === id) ?? null;
    }

    // Every line-append and the terminal state both go through one
    // reassignment of the whole `jobs` array (the standard "reassign to
    // notify" QML idiom, same reasoning UsageStore.qml documents) rather
    // than in-place mutation. Known tradeoff: a very chatty command
    // reassigns + re-serializes every tracked job on every line. Acceptable
    // for admin-command output (a handful of jobs, human-paced volume);
    // revisit with SystemStats.qml's ring-buffer-plus-tick-counter trick if
    // a real job ever floods this.
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

    // Guarded idempotent: onExited and onErrorOccurred can both fire for a
    // failed launch (e.g. command not found), and this must only finalize
    // the job once.
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

            // NOT a real Signal -- Process's qmltypes lists this as a plain
            // Method (like PamContext's onMessage/onCompleted/onError,
            // documented in LockService.qml), so the ordinary `onX: handler`
            // property-assignment form fails with "Cannot assign to
            // non-existent property" (confirmed live in staging). Since
            // Process IS instantiated directly by us here (unlike AuthFlow,
            // which is handed to us as a pointer), the override-function
            // convention applies: declare it as a real function with the
            // exact method name instead.
            function onErrorOccurred(error) {
                root._finishJob(proc.jobId, -1);
            }
        }
    }
}
