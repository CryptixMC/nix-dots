pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Every file-mutating (and a few read-then-act) command the Files tab runs
// funnels through one serial job queue behind a single reusable Process --
// simpler and safer than one Process per action type, and it means two
// rapid actions (e.g. a double-click delete) can't race each other's
// stdout/stderr. Directory *listing* deliberately does NOT go through here
// -- FilesPane.qml and FilesTree.qml each own their own dedicated Process
// for that, so a slow compress/extract job can never stall the UI's
// ability to just look at a directory.
//
// Anything that mutates the current directory's contents bumps
// FilesState.refreshToken on success so the active listing re-reads
// without the caller needing to know that's how it works. Failures surface
// real stderr via opFailed instead of failing silently the way the old
// fire-and-forget Quickshell.execDetached did.
QtObject {
    id: root

    signal opFailed(string message)

    // Gates the Compress submenu's Zip entry -- zip/7z aren't installed on
    // this machine as of this pass (unlike tar/xz/zstd/unzip, all present),
    // so the entry only appears once the tool actually exists rather than
    // failing at click time. One combined probe, not three separate
    // Processes, matching SystemTab.qml's own single-Process-per-snapshot
    // idiom.
    property var availableTools: ({})

    Component.onCompleted: {
        root._enqueue(["sh", "-c", "for c in zip 7z; do command -v \"$c\" >/dev/null 2>&1 && echo \"$c=1\" || echo \"$c=0\"; done"], (out) => {
            const map = {};
            for (const line of out.split("\n")) {
                const eq = line.indexOf("=");
                if (eq > 0)
                    map[line.slice(0, eq)] = line.slice(eq + 1) === "1";
            }
            root.availableTools = map;
        }, false);
    }

    property var _queue: []
    property bool _busy: false

    function _enqueue(argv, onDone, refresh, cwd) {
        root._queue.push({
            argv: argv,
            onDone: onDone ?? null,
            refresh: refresh ?? false,
            cwd: cwd ?? ""
        });
        root._pump();
    }

    function _pump() {
        if (root._busy || root._queue.length === 0)
            return;
        root._busy = true;
        const job = root._queue[0];
        runner.onDoneCb = job.onDone;
        runner.refreshOnSuccess = job.refresh;
        runner.workingDirectory = job.cwd;
        runner.command = job.argv;
        runner.running = true;
    }

    property Process runner: Process {
        id: runner
        property var onDoneCb: null
        property bool refreshOnSuccess: false

        stdout: StdioCollector {
            id: runnerOut
        }
        stderr: StdioCollector {
            id: runnerErr
        }

        onExited: (exitCode, exitStatus) => {
            root._queue.shift();
            if (exitCode === 0) {
                if (runner.refreshOnSuccess)
                    FilesState.refreshToken = FilesState.refreshToken + 1;
                if (runner.onDoneCb)
                    runner.onDoneCb(runnerOut.text);
            } else {
                const msg = runnerErr.text.trim();
                root.opFailed(msg.length > 0 ? msg : `Command failed (exit code ${exitCode})`);
            }
            root._busy = false;
            root._pump();
        }
    }

    // ---- filesystem mutation ----

    function newFolder(dir, name) {
        root._enqueue(["mkdir", "-p", "--", `${dir}/${name}`], null, true);
    }

    function newFile(dir, name) {
        root._enqueue(["touch", "--", `${dir}/${name}`], null, true);
    }

    function rename(oldPath, newPath) {
        root._enqueue(["mv", "-n", "--", oldPath, newPath], null, true);
    }

    // `overwrite` gates `-n` -- the caller must already have shown
    // FilesState's collision-confirm row before passing true, this
    // function itself has no confirmation of its own.
    function move(paths, destDir, overwrite) {
        const args = ["mv"];
        if (!overwrite)
            args.push("-n");
        args.push("--", ...paths, destDir);
        root._enqueue(args, null, true);
    }

    function copy(paths, destDir, overwrite) {
        const args = ["cp", "-r"];
        if (!overwrite)
            args.push("-n");
        args.push("--", ...paths, destDir);
        root._enqueue(args, null, true);
    }

    // Trash, never rm -- the launcher has no permanent-delete path
    // anywhere, by design (see the plan's "Trash + confirm" decision).
    function trash(paths) {
        root._enqueue(["trash-put", "--", ...paths], null, true);
    }

    // `paths` are archived by their basenames (relative to `baseDir`) so
    // the archive doesn't embed the current directory's full absolute
    // path -- matches what a user expects from "compress this folder".
    function compress(format, paths, destArchive, baseDir) {
        const names = paths.map(p => p.split("/").pop());
        switch (format) {
        case "tar.gz":
            root._enqueue(["tar", "-czf", destArchive, "-C", baseDir, ...names], null, true);
            break;
        case "tar.zst":
            root._enqueue(["tar", "--zstd", "-cf", destArchive, "-C", baseDir, ...names], null, true);
            break;
        case "tar.xz":
            root._enqueue(["tar", "-cJf", destArchive, "-C", baseDir, ...names], null, true);
            break;
        case "zip":
            // zip has no tar-style `-C`; run it with baseDir as the
            // process's own cwd instead so `-r` still archives relative
            // names, not absolute paths.
            root._enqueue(["zip", "-r", destArchive, ...names], null, true, baseDir);
            break;
        }
    }

    function extract(archivePath, destDir) {
        const lower = archivePath.toLowerCase();
        const argv = lower.endsWith(".zip") ? ["unzip", "-o", archivePath, "-d", destDir] : ["tar", "-xf", archivePath, "-C", destDir];
        root._enqueue(argv, null, true);
    }

    // ---- clipboard ----

    // Positional argument, not piped stdin -- Process has no explicit
    // close-stdin primitive (SKILL.md), and wl-copy's own argv mode sidesteps
    // that race entirely.
    function copyTextToClipboard(text) {
        root._enqueue(["wl-copy", "--", text], null, false);
    }

    // ---- Open With ----

    // xdg-mime -> gio mime is the only path to "what can open this file" --
    // Quickshell's DesktopEntry has no mimeTypes property (confirmed
    // against quickshell-core.qmltypes), so this can't be done from
    // DesktopEntries alone.
    function queryOpenWith(path, callback) {
        root._enqueue(["xdg-mime", "query", "filetype", path], (mimeOut) => {
            const mime = mimeOut.trim();
            if (mime.length === 0) {
                callback([]);
                return;
            }
            root._enqueue(["gio", "mime", mime], (gioOut) => {
                const ids = new Set();
                for (const line of gioOut.split("\n")) {
                    const t = line.trim();
                    if (t.endsWith(".desktop"))
                        ids.add(t);
                }
                callback([...ids]);
            }, false);
        }, false);
    }

    // Launches through the resolved DesktopEntry's own .command/
    // .runInTerminal, the same mechanism Launcher.qml's root.launch() uses
    // for the Applications tab -- NOT `gio launch`, which (confirmed live)
    // takes a literal filesystem path to the .desktop file rather than
    // resolving a bare id against XDG_DATA_DIRS, making it the wrong tool
    // here without an extra resolution step DesktopEntries.byId() already
    // does for free.
    function launchEntryWith(entry, path) {
        if (!entry)
            return;
        if (entry.runInTerminal)
            Quickshell.execDetached({
                command: ["ghostty", "-e", ...entry.command, path],
                workingDirectory: entry.workingDirectory
            });
        else
            Quickshell.execDetached({
                command: [...entry.command, path],
                workingDirectory: entry.workingDirectory
            });
    }

    // ---- properties ----

    // Three direct-argv calls, never a shell string built from `path` --
    // filenames with spaces/quotes/`$()` are common enough (real example
    // elsewhere in this repo: Prism's "Arcadia [RPG] new" instance name)
    // that a bash -lc interpolation would be both wrong and a real
    // injection risk. Process's array-form `command` never invokes a
    // shell, so none of that applies here.
    function propertiesFor(path, callback) {
        root._enqueue(["stat", "--format=%s|%Y|%A|%U:%G|%F", "--", path], (statOut) => {
            root._enqueue(["du", "-sh", "--", path], (duOut) => {
                root._enqueue(["xdg-mime", "query", "filetype", path], (mimeOut) => {
                    const parts = statOut.trim().split("|");
                    callback({
                        size: parseInt(parts[0], 10) || 0,
                        mtimeEpoch: parseFloat(parts[1]) || 0,
                        perms: parts[2] ?? "",
                        owner: parts[3] ?? "",
                        kind: parts[4] ?? "",
                        diskUsage: (duOut.trim().split("\t")[0]) ?? "",
                        mime: mimeOut.trim()
                    });
                }, false);
            }, false);
        }, false);
    }
}
