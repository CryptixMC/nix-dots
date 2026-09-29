pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Serial job queue for file-mutating commands, behind one Process so rapid
// actions can't race. Directory listing has its own Processes (FilesPane/FilesTree)
// so slow jobs never stall browsing. Successful mutations bump
// FilesState.refreshToken; failures surface stderr via opFailed.
QtObject {
    id: root

    signal opFailed(string message)

    // Detected tools (e.g. zip/7z); gates menu entries so they don't fail at click time.
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

    // `overwrite` drops `-n`; the caller must have confirmed the collision already.
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

    // Trash, never rm: the launcher has no permanent-delete path by design.
    function trash(paths) {
        root._enqueue(["trash-put", "--", ...paths], null, true);
    }

    // Archives by basename relative to `baseDir`, not full absolute paths.
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
            // zip has no `-C`, so run it with baseDir as cwd to keep names relative.
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

    // Argv, not stdin: Process can't explicitly close stdin.
    function copyTextToClipboard(text) {
        root._enqueue(["wl-copy", "--", text], null, false);
    }

    // ---- Open With ----

    // Quickshell's DesktopEntry has no mimeTypes, so query xdg-mime/gio instead.
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

    // Launches via the DesktopEntry's command/runInTerminal, like Launcher.qml's
    // launch(). Not `gio launch`, which needs a .desktop file path rather than an id.
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

    // Direct argv, never a shell string built from `path`: filenames with quotes or
    // `$()` would break it and be an injection risk.
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
