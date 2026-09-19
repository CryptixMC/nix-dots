import QtQuick
import Quickshell
import Quickshell.Io

// Makes the chat panel notice turns written by something that isn't this
// client -- in practice, Goose Desktop.
//
// Why a poll and not a push: Goose Desktop is not a qubi-engine client at
// all. It drives its own `goose serve` over a private loopback port,
// while this shell talks ACP to qubi-engine. Two disjoint process trees;
// the ONLY state they share is goose's own sessions.db. SQLite has no
// change feed, and watching the file is unreliable because WAL mode means
// writes land in sessions.db-wal rather than the db path itself. A cheap
// indexed query is both more dependable and yields the token counts the
// status bar needs anyway.
//
// This only makes the Quickshell direction live. Desktop picking up turns
// written here still depends on Desktop's own refresh behaviour, which
// this repo does not control.
Item {
    id: root

    required property string sessionId

    readonly property string dbPath: `${Quickshell.env("HOME")}/.local/share/goose/sessions/sessions.db`
    property int pollIntervalMs: 3000

    // Highest messages.id already accounted for. The cursor is the row id,
    // NOT created_timestamp: timestamps are second-resolution and really
    // do collide (a prompt and its synthetic turn-context row share one),
    // so a `> timestamp` cursor silently drops messages. id is
    // INTEGER PRIMARY KEY AUTOINCREMENT, so it is strictly increasing.
    property int cursor: -1

    signal externalMessages(var entries)
    signal tokensUpdated(int total, int accumulated)

    onSessionIdChanged: {
        // A different conversation is open: re-baseline rather than
        // replaying the new session's history as if it were new traffic
        // (the ACP session/load path already replays history properly).
        root.cursor = -1;
        if (root.sessionId.length > 0)
            adopt();
    }

    // Move the cursor to the session's current tail WITHOUT emitting
    // anything. Used at open, and after every locally-driven turn: those
    // messages are already on screen from the live ACP stream, so
    // replaying them from the db would duplicate the whole exchange.
    function adopt() {
        if (root.sessionId.length === 0 || adoptProcess.running)
            return;
        adoptProcess.command = ["sqlite3", "-json", root.dbPath, `SELECT COALESCE(MAX(id), 0) AS maxId, (SELECT COALESCE(total_tokens, 0) FROM sessions WHERE id = '${root.sessionId}') AS total, (SELECT COALESCE(accumulated_total_tokens, 0) FROM sessions WHERE id = '${root.sessionId}') AS accumulated FROM messages WHERE session_id = '${root.sessionId}'`];
        adoptProcess.running = true;
    }

    // goose stores each message as an array of typed parts. Only plain
    // text parts are conversation; `thinking` parts are reasoning traces
    // (the live stream renders those separately), and every turn also
    // carries a synthetic <turn-context> user row that is scaffolding,
    // not something the human said -- verified directly in the real db.
    function _plainText(contentJson) {
        let parts;
        try {
            parts = JSON.parse(contentJson);
        } catch (e) {
            return "";
        }
        if (!Array.isArray(parts))
            return "";
        return parts.filter(p => p.type === "text").map(p => p.text ?? "").join("").trim();
    }

    function _isScaffolding(text) {
        return text.startsWith("<turn-context>");
    }

    function _rowsToEntries(rows) {
        const entries = [];
        for (const r of rows) {
            if (r.id > root.cursor)
                root.cursor = r.id;
            const body = root._plainText(r.content_json);
            if (body.length === 0 || root._isScaffolding(body))
                continue;
            entries.push({
                role: r.role === "user" ? "user" : "assistant",
                text: body,
                time: Qt.formatDateTime(new Date(r.created_timestamp * 1000), "hh:mm")
            });
        }
        return entries;
    }

    // Rebuild a resumed conversation from the db.
    //
    // ACP's own session/load replay is unreliable: measured directly
    // against the live engine, one session replayed its history fine
    // while two others -- including one with six real messages in the db
    // -- replayed nothing at all and resumed to a blank panel. Since
    // sessions.db is the actual system of record for both this client and
    // Goose Desktop, reading it is strictly more dependable than trusting
    // the replay. Only used when the replay genuinely produced nothing,
    // so a working replay is never second-guessed or duplicated.
    function backfill() {
        if (root.sessionId.length === 0 || backfillProcess.running)
            return;
        backfillProcess.command = ["sqlite3", "-json", root.dbPath, `SELECT id, role, content_json, created_timestamp FROM messages WHERE session_id = '${root.sessionId}' ORDER BY id`];
        backfillProcess.running = true;
    }

    Process {
        id: backfillProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let rows;
                try {
                    rows = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (!Array.isArray(rows) || rows.length === 0)
                    return;
                const entries = root._rowsToEntries(rows);
                if (entries.length > 0)
                    root.externalMessages(entries);
                root.adopt();
            }
        }
    }

    Process {
        id: adoptProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const rows = JSON.parse(text);
                    if (rows.length > 0) {
                        root.cursor = rows[0].maxId;
                        root.tokensUpdated(rows[0].total ?? 0, rows[0].accumulated ?? 0);
                    }
                } catch (e) {
                    // A transient SQLITE_BUSY (13 goose processes hold this
                    // db open) yields empty/garbage output. Staying on the
                    // old cursor and retrying next tick is correct; surfacing
                    // it would be noise.
                }
            }
        }
    }

    Process {
        id: pollProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let rows;
                try {
                    rows = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (!Array.isArray(rows) || rows.length === 0)
                    return;
                const entries = root._rowsToEntries(rows);
                if (entries.length > 0)
                    root.externalMessages(entries);
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        repeat: true
        // Driven by the parent (gated on panel visibility + not busy) so
        // there is no background cost while the panel is closed.
        running: false
        onTriggered: {
            // Never stack queries: this db is contended, and a slow tick
            // must not queue another behind it.
            if (root.sessionId.length === 0 || pollProcess.running || adoptProcess.running)
                return;
            if (root.cursor < 0) {
                root.adopt();
                return;
            }
            pollProcess.command = ["sqlite3", "-json", root.dbPath, `SELECT id, role, content_json, created_timestamp FROM messages WHERE session_id = '${root.sessionId}' AND id > ${root.cursor} ORDER BY id`];
            pollProcess.running = true;
        }
    }

    function setPolling(on) {
        pollTimer.running = on;
    }
}
