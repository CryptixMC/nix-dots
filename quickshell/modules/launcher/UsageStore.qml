pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Frecency-style ranking data for the launcher: frequency + recency,
// decayed over time — not pure last-used-wins, so an app opened constantly
// still outranks one opened once yesterday. Persisted as a flat
// {"<desktop-entry-id>": {count, lastUsed}} map so ranking survives a
// Quickshell restart. Root is a FileView directly (pragma Singleton doesn't
// require a QtObject root) with a JsonAdapter as its default `adapter`
// child, matching Quickshell's standard persisted-settings pattern.
FileView {
    id: root

    // XDG state home — survives reboots, unlike the ephemeral
    // XDG_RUNTIME_DIR quickshell itself uses for its own logs/sockets.
    path: `${Quickshell.env("HOME")}/.local/state/quickshell-launcher-usage.json`
    watchChanges: false
    printErrors: false

    // First run: no file on disk yet. Deferred to the first actual
    // recordLaunch() call rather than seeded eagerly here — calling
    // setText() synchronously from inside onLoadFailed hit a FileView
    // operation-queue reentrancy warning ("got operation finished from
    // dropped operation") and silently failed to create the file; doing it
    // lazily from a plain function call sidesteps that entirely, and there's
    // nothing to persist until the first launch anyway.
    property bool needsSeed: false
    onLoadFailed: error => root.needsSeed = true

    JsonAdapter {
        property var usage: ({})
    }

    function recordLaunch(entryId) {
        if (!entryId)
            return;
        // writeAdapter() below can only update an *existing* file, not
        // create a missing one (confirmed empirically — silently no-ops
        // otherwise); setText() is the one call that can create it.
        if (root.needsSeed) {
            root.setText("{}");
            root.needsSeed = false;
        }
        const current = root.adapter.usage[entryId] ?? {
            count: 0,
            lastUsed: 0
        };
        // Reassigning the whole object (not usage[entryId] = ...) is
        // required for the JsonAdapter to notice the change and persist it
        // — mutating a `var` property's contents in place doesn't trigger
        // QML's property-changed notification. Object.assign rather than
        // {...spread}: this QML JS engine doesn't support spread inside
        // object literals (confirmed via a live reload error — array
        // spread in a function call, used elsewhere in Launcher.qml, is
        // fine; this is specifically about object-literal spread).
        const next = Object.assign({}, root.adapter.usage);
        next[entryId] = {
            count: current.count + 1,
            lastUsed: Date.now()
        };
        root.adapter.usage = next;
        root.writeAdapter();
    }

    // Exponential decay, ~4 day half-life: an app used 10x a week ago can
    // still edge out one used twice today, but the gap closes fast enough
    // that genuinely stale entries fall away on their own without needing
    // to prune the store.
    function score(entryId) {
        const rec = root.adapter.usage[entryId];
        if (!rec)
            return 0;
        const ageDays = (Date.now() - rec.lastUsed) / (1000 * 60 * 60 * 24);
        return rec.count * Math.pow(0.5, ageDays / 4);
    }
}
