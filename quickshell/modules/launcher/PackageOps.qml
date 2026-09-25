pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The only thing permitted to edit modules/{home-manager,nixos}/core/
// packages.nix. Every write is: validated (attr shape, not already
// declared), guarded (refuses to land on top of unrelated uncommitted
// changes to that file, unless we're the ones who dirtied it), atomic
// (temp file + mv, never in-place truncation), and recorded to a pending
// list persisted to disk (~/.local/state/quickshell-pending-packages.json,
// same FileView+JsonAdapter pattern as UsageStore.qml) so a Quickshell
// restart doesn't orphan an in-flight edit.
//
// Routed through JobRunner rather than a private Process -- the insert is
// a real filesystem mutation worth showing in the Jobs section's output
// pane like any other consequential action, and it's unprivileged (editing
// files in $HOME needs no elevation), so JobRunner just runs it directly.
//
// Deliberately narrow: only the two general list sites (home-manager/core
// and nixos/core), only a single top-level bare attribute (no `foo.bar`
// nesting -- nix attrs CAN nest, but validating and writing that safely is
// out of scope for this pass), and only via the one `];`-shaped list each
// file has today. Both are the only sites the plan calls "safe to edit";
// the six topical sites stay PackageDeclarations-read-only forever.
Item {
    id: root

    readonly property string repoRoot: `${Quickshell.env("HOME")}/nix-dots`

    function _siteFor(scope) {
        return scope === "user" ? "modules/home-manager/core/packages.nix" : "modules/nixos/core/packages.nix";
    }

    // Nix bare-identifier attrs only -- same shape PackageDeclarations
    // parses out, re-validated here independently since nix-search results
    // (an entirely different source) feed this function too and are not
    // pre-validated by that parser.
    function _validAttr(attr) {
        return /^[a-zA-Z_][a-zA-Z0-9_'-]*$/.test(attr);
    }

    property int _busyJobId: -1
    property var _busyEntry: null

    function _addPending(entry) {
        const next = pendingStore.adapter.entries.concat([entry]);
        pendingStore.adapter.entries = next;
        pendingStore.persist();
    }

    function _removePending(attr, file) {
        const next = pendingStore.adapter.entries.filter(e => !(e.attr === attr && e.file === file));
        pendingStore.adapter.entries = next;
        pendingStore.persist();
    }

    function isPendingFile(relPath) {
        return pendingStore.adapter.entries.some(e => e.file === relPath);
    }

    // opts.onDone(ok: bool, message: string) -- fired once the job settles.
    function addToConfig(attr, scope, onDone) {
        if (root._busyJobId >= 0) {
            onDone?.(false, "another package operation is already in flight");
            return;
        }
        if (!root._validAttr(attr)) {
            onDone?.(false, `"${attr}" isn't a plain top-level attribute -- not supported by this pass`);
            return;
        }
        if (PackageDeclarations.isDeclared(attr)) {
            onDone?.(false, `"${attr}" is already declared`);
            return;
        }
        const relPath = root._siteFor(scope);
        const alreadyPending = root.isPendingFile(relPath) ? "1" : "0";
        const script = `
set -e
cd "$1"
if [ "$4" = "0" ] && ! git diff --quiet -- "$2"; then
  echo "REFUSED: $2 has unrelated uncommitted changes -- commit or stash first" >&2
  exit 3
fi
awk -v attr="    $3" '
  /\\];/ && !done { print attr; done=1 }
  { print }
' "$2" > "$2.tmp.$$" && mv "$2.tmp.$$" "$2"
`;
        root._busyEntry = { attr, scope, file: relPath, action: "add", timestamp: Date.now() };
        root._busyJobId = JobRunner.run(`Add ${attr} to config`, ["sh", "-c", script, "sh", root.repoRoot, relPath, attr, alreadyPending], { privileged: false, cwd: root.repoRoot });
        root._pendingOnDone = onDone;
    }

    function revert(entry, onDone) {
        if (root._busyJobId >= 0) {
            onDone?.(false, "another package operation is already in flight");
            return;
        }
        const script = `
set -e
cd "$1"
awk -v attr="    $3" '
  $0 == attr && !done { done=1; next }
  { print }
' "$2" > "$2.tmp.$$" && mv "$2.tmp.$$" "$2"
`;
        root._busyEntry = Object.assign({}, entry, { action: "revert" });
        root._busyJobId = JobRunner.run(`Revert ${entry.attr}`, ["sh", "-c", script, "sh", root.repoRoot, entry.file, entry.attr], { privileged: false, cwd: root.repoRoot });
        root._pendingOnDone = onDone;
    }

    property var _pendingOnDone: null

    Connections {
        target: JobRunner
        function onJobsChanged() {
            if (root._busyJobId < 0)
                return;
            const job = JobRunner.jobById(root._busyJobId);
            if (!job || job.state === "running")
                return;
            const ok = job.state === "ok";
            const entry = root._busyEntry;
            root._busyJobId = -1;
            root._busyEntry = null;
            const cb = root._pendingOnDone;
            root._pendingOnDone = null;

            if (ok) {
                if (entry.action === "add")
                    root._addPending(entry);
                else if (entry.action === "revert")
                    root._removePending(entry.attr, entry.file);
                PackageDeclarations.reload();
            }
            cb?.(ok, ok ? "" : (job.output.join("\n") || "command failed"));
        }
    }

    // Persisted pending-edit list -- same FileView+JsonAdapter pattern
    // UsageStore.qml uses, including its setText("{}")-before-first-write
    // seeding gotcha (writeAdapter() alone can't create a missing file).
    FileView {
        id: pendingStore
        path: `${Quickshell.env("HOME")}/.local/state/quickshell-pending-packages.json`
        watchChanges: false
        printErrors: false

        property bool needsSeed: false
        onLoadFailed: error => pendingStore.needsSeed = true

        JsonAdapter {
            property var entries: []
        }

        function persist() {
            if (pendingStore.needsSeed) {
                pendingStore.setText("{}");
                pendingStore.needsSeed = false;
            }
            pendingStore.writeAdapter();
        }
    }

    // Plain binding, not an alias -- alias targets need a simple id.property
    // path, and this is two levels deep (pendingStore.adapter.entries).
    // Reactive same as any other binding since entries is always reassigned
    // wholesale, never mutated in place (see _addPending/_removePending).
    readonly property var pending: pendingStore.adapter.entries
}
