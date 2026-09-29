pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Frecency ranking data for the launcher, persisted as a
// {"<desktop-entry-id>": {count, lastUsed}} map so it survives restarts.
FileView {
    id: root

    // XDG state home, so it survives reboots.
    path: `${Quickshell.env("HOME")}/.local/state/quickshell-launcher-usage.json`
    watchChanges: false
    printErrors: false

    // No file on disk yet. Seeding is deferred to the first recordLaunch():
    // calling setText() inside onLoadFailed hits a FileView reentrancy bug and fails.
    property bool needsSeed: false
    onLoadFailed: error => root.needsSeed = true

    JsonAdapter {
        property var usage: ({})
    }

    function recordLaunch(entryId) {
        if (!entryId)
            return;
        // writeAdapter() can't create a missing file; only setText() can.
        if (root.needsSeed) {
            root.setText("{}");
            root.needsSeed = false;
        }
        const current = root.adapter.usage[entryId] ?? {
            count: 0,
            lastUsed: 0
        };
        // Reassign the whole object so JsonAdapter notices the change. Object.assign
        // because this JS engine doesn't support object-literal spread.
        const next = Object.assign({}, root.adapter.usage);
        next[entryId] = {
            count: current.count + 1,
            lastUsed: Date.now()
        };
        root.adapter.usage = next;
        root.writeAdapter();
    }

    // Exponential decay with a ~4 day half-life, so stale entries fade without pruning.
    function score(entryId) {
        const rec = root.adapter.usage[entryId];
        if (!rec)
            return 0;
        const ageDays = (Date.now() - rec.lastUsed) / (1000 * 60 * 60 * 24);
        return rec.count * Math.pow(0.5, ageDays / 4);
    }
}
