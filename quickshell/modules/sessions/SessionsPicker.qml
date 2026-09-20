import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../chat"

// Session-history picker: browse past qubi sessions and resume one into
// the chat overlay. Structural template is Launcher.qml/ChatOverlay.qml
// (centered PanelWindow, Overlay layer, click-outside/Escape close) — not
// a literal include, this module has its own two-pane (list + preview)
// layout instead of tabs, so none of Launcher's per-tab Loader machinery
// applies here.
//
// Data source is deliberately the real ACP `session/list` method
// (GooseAcpSession.listSessions), not the `goose session list` CLI command
// — confirmed live that the CLI command silently only returns
// session_type:"user" sessions and excludes every session_type:"acp" one,
// which is exactly what this chat overlay creates (6 vs. 48 rows in the
// raw sessions.db when compared directly). The CLI would make every
// session this app itself creates invisible in its own history picker.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: SessionsState.visible
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    property int selectedIndex: -1

    // The list the UI actually renders: SessionsState.sessions minus the
    // empty shells when the filter is on. selectedIndex indexes THIS list,
    // never the raw one -- mixing the two would resume/delete whichever
    // session happened to sit at that position in the unfiltered array.
    readonly property var visibleSessions: SessionsState.hideEmpty ? SessionsState.sessions.filter(s => (s._meta?.messageCount ?? 0) > 0) : SessionsState.sessions
    readonly property var selectedSession: (selectedIndex >= 0 && selectedIndex < visibleSessions.length) ? visibleSessions[selectedIndex] : null

    readonly property string dbPath: `${Quickshell.env("HOME")}/.local/share/goose/sessions/sessions.db`

    // Session ids are goose-generated ("20260919_53"), but this value is
    // interpolated straight into SQL, so it is whitelisted rather than
    // trusted -- a stray quote would otherwise end the string literal.
    function safeId(id) {
        return String(id ?? "").replace(/[^A-Za-z0-9_-]/g, "");
    }

    // ---- preview ------------------------------------------------------
    //
    // Deliberately cheap: ONE sqlite3 process per selection, two indexed
    // LIMIT queries unioned, no model call anywhere. The "summary" is just
    // the conversation's opening question, which is what a human actually
    // scans for when finding an old chat -- generating a real summary would
    // mean running inference over every session you click, which on this
    // hardware costs tens of seconds per session (measured: 60s for "what is
    // 6 times 7").
    property var previewFirst: []
    property var previewRecent: []
    property bool previewLoading: false
    property string previewFor: ""

    function loadPreview() {
        const sid = root.safeId(root.selectedSession?.sessionId);
        root.previewFirst = [];
        root.previewRecent = [];
        root.previewFor = sid;
        if (sid.length === 0 || previewProcess.running)
            return;
        root.previewLoading = true;
        previewProcess.command = ["sqlite3", "-json", root.dbPath, `SELECT * FROM (SELECT 'first' AS kind, id, role, content_json FROM messages WHERE session_id='${sid}' AND role='user' ORDER BY id ASC LIMIT 5) UNION ALL SELECT * FROM (SELECT 'recent' AS kind, id, role, content_json FROM messages WHERE session_id='${sid}' ORDER BY id DESC LIMIT 12)`];
        previewProcess.running = true;
    }

    // goose stores each message as an array of typed parts; only `text`
    // parts are conversation. Same shape SessionSync.qml parses -- and the
    // same synthetic <turn-context> scaffolding row has to be skipped here
    // too, or every preview opens with a wall of injected context instead of
    // what the human typed.
    function plainText(contentJson) {
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

    function isScaffolding(text) {
        return text.startsWith("<turn-context>");
    }

    Process {
        id: previewProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewLoading = false;
                let rows;
                try {
                    rows = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (!Array.isArray(rows))
                    return;
                const first = [];
                const recent = [];
                for (const r of rows) {
                    const body = root.plainText(r.content_json);
                    if (body.length === 0 || root.isScaffolding(body))
                        continue;
                    const entry = {
                        role: r.role,
                        text: body
                    };
                    if (r.kind === "first")
                        first.push(entry);
                    else
                        recent.push(entry);
                }
                root.previewFirst = first;
                // The recent half came back newest-first (ORDER BY id DESC)
                // so it reads bottom-up until reversed.
                root.previewRecent = recent.reverse();
            }
        }
    }

    // ---- delete -------------------------------------------------------
    //
    // `goose session remove --session-id X` is the sanctioned path but is
    // unusable here: it always prompts for confirmation on a real TTY and
    // dies with "Error: not connected" under any non-interactive parent,
    // which every Quickshell Process is. So the rows are removed directly,
    // in one transaction, covering all three things that reference a
    // session: messages, usage_ledger, and the self-referential
    // parent_session_id. Verified against the live db -- integrity_check and
    // foreign_key_check both clean afterwards.
    property string confirmDeleteId: ""

    function deleteSelected() {
        const sid = root.safeId(root.selectedSession?.sessionId);
        if (sid.length === 0 || deleteProcess.running)
            return;
        // Never delete the conversation currently open in the chat panel.
        if (sid === GooseAcpSession.sessionId) {
            SessionsState.loadError = "That session is currently open in the chat panel — close or switch it first.";
            root.confirmDeleteId = "";
            return;
        }
        deleteProcess.command = ["sqlite3", root.dbPath, `PRAGMA foreign_keys=ON; BEGIN IMMEDIATE; DELETE FROM messages WHERE session_id='${sid}'; DELETE FROM usage_ledger WHERE session_id='${sid}'; UPDATE sessions SET parent_session_id=NULL WHERE parent_session_id='${sid}'; DELETE FROM sessions WHERE id='${sid}'; COMMIT;`];
        deleteProcess.running = true;
    }

    Process {
        id: deleteProcess
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    SessionsState.loadError = `delete failed: ${text.trim()}`;
            }
        }
        onExited: exitCode => {
            root.confirmDeleteId = "";
            root.selectedIndex = -1;
            if (exitCode === 0)
                root.refresh();
        }
    }

    function refresh() {
        SessionsState.loading = true;
        SessionsState.loadError = "";
        root.selectedIndex = -1;
        GooseAcpSession.listSessions((sessions, error) => {
            SessionsState.loading = false;
            // Newest first, matching the CLI's own default ordering.
            SessionsState.sessions = sessions.slice().sort((a, b) => (b.updatedAt ?? "").localeCompare(a.updatedAt ?? ""));
        });
    }

    // Buffered, not appended straight to ChatState per-message -- see
    // ChatState.appendMessages' own comment for the real "chat loading/
    // resuming feels slow" bug this fixes. historyMessage signals arrive
    // (and this buffer fills) for the whole replay before historyLoaded
    // fires, since that signal only fires once session/load's own
    // JSON-RPC *result* arrives, which is ordered after every notification
    // line a real ACP process sends on stdout -- GooseAcpSession.qml's own
    // _loadingHistory/historyLoaded design already depends on this same
    // ordering guarantee.
    property var _historyBuffer: []

    function resumeSelected() {
        if (!root.selectedSession)
            return;
        ChatState.clear();
        root._historyBuffer = [];
        GooseAcpSession.loadSession(root.selectedSession.sessionId, error => {
            if (error) {
                SessionsState.loadError = "This session cannot be resumed (it was created by qubi-code and the underlying Goose engine has a known limitation loading recipe-based sessions).";
            } else {
                SessionsState.hide();
                ChatState.visible = true;
            }
        });
    }

    Connections {
        target: GooseAcpSession
        function onHistoryMessage(role, text) {
            root._historyBuffer.push({
                role: role,
                text: text
            });
        }
        function onHistoryLoaded() {
            ChatState.appendMessages(root._historyBuffer);
            root._historyBuffer = [];
        }
    }

    onVisibleChanged: {
        if (visible)
            root.refresh();
    }

    Shortcut {
        sequence: "Escape"
        onActivated: SessionsState.hide()
    }

    IpcHandler {
        target: "sessions"
        function toggle(): void {
            SessionsState.toggle();
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: SessionsState.hide()
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: Theme.spacing.launcherWidthWide
        height: Math.min(parent.height * 0.75, 720)
        radius: Theme.radius.panel
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
        }

        Row {
            anchors {
                fill: parent
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            Rectangle {
                width: Theme.spacing.sessionListWidth
                height: parent.height
                color: "transparent"

                Row {
                    id: filterRow
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: Theme.spacing.launcherTabHeight
                    spacing: Theme.spacing.launcherIconLabelGap

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 150
                        height: Theme.spacing.launcherTabHeight - 6
                        radius: Theme.radius.input
                        color: SessionsState.hideEmpty ? Theme.color.launcherItemSelectedBg : "transparent"
                        border.width: Theme.spacing.borderHairline
                        border.color: SessionsState.hideEmpty ? Theme.color.launcherInputBorder : Theme.color.launcherBorder

                        Text {
                            anchors.centerIn: parent
                            text: SessionsState.hideEmpty ? "✓ hiding empty" : "showing all"
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                SessionsState.hideEmpty = !SessionsState.hideEmpty;
                                // The filtered list is about to change shape,
                                // so a held index would point at a different
                                // session than the one highlighted.
                                root.selectedIndex = -1;
                                root.confirmDeleteId = "";
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${root.visibleSessions.length} / ${SessionsState.sessions.length}`
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                }

                ListView {
                    id: sessionList
                    anchors {
                        top: filterRow.bottom
                        topMargin: Theme.spacing.sessionMetaGap
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    clip: true
                    spacing: Theme.spacing.sessionRowGap
                    model: root.visibleSessions

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index

                        width: sessionList.width
                        height: Theme.spacing.sessionRowHeight
                        radius: Theme.radius.input
                        color: root.selectedIndex === index ? Theme.color.launcherItemSelectedBg : "transparent"

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedIndex = row.index;
                                SessionsState.loadError = "";
                                // Selecting a different session abandons any
                                // half-confirmed delete on the previous one.
                                root.confirmDeleteId = "";
                                root.loadPreview();
                            }
                            onDoubleClicked: {
                                root.selectedIndex = row.index;
                                root.resumeSelected();
                            }
                        }

                        Column {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                margins: Theme.spacing.sessionRowPadX
                            }
                            spacing: Theme.spacing.sessionMetaGap

                            Text {
                                width: parent.width
                                text: row.modelData.title ?? "New Chat"
                                elide: Text.ElideRight
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                            }
                            Text {
                                width: parent.width
                                text: {
                                    const meta = row.modelData._meta ?? {};
                                    const when = (row.modelData.updatedAt ?? "").replace("T", " ").replace(/\+.*/, "");
                                    return `${meta.messageCount ?? 0} messages · ${meta.modelId ?? "?"} · ${when}`;
                                }
                                elide: Text.ElideRight
                                color: Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - Theme.spacing.sessionListWidth - parent.spacing
                height: parent.height
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg

                Column {
                    anchors {
                        fill: parent
                        margins: Theme.spacing.sessionPreviewPad
                    }
                    spacing: Theme.spacing.launcherContentGap

                    Text {
                        visible: root.selectedSession !== null
                        width: parent.width
                        text: root.selectedSession?.title ?? ""
                        wrapMode: Text.Wrap
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        font.bold: true
                    }

                    Text {
                        visible: root.selectedSession !== null
                        width: parent.width
                        text: {
                            if (!root.selectedSession)
                                return "";
                            const meta = root.selectedSession._meta ?? {};
                            return `${root.selectedSession.cwd ?? ""}\n${meta.providerId ?? "?"} / ${meta.modelId ?? "?"}\n${meta.messageCount ?? 0} messages`;
                        }
                        wrapMode: Text.Wrap
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    Text {
                        visible: root.selectedSession === null
                        width: parent.width
                        text: SessionsState.loading ? "loading sessions…" : "select a session to see details"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                    }

                    // Cheap stand-in for a summary: the conversation's own
                    // opening question. No inference, one indexed query.
                    Text {
                        visible: root.selectedSession !== null && root.previewFirst.length > 0
                        width: parent.width
                        text: {
                            const opener = root.previewFirst.find(e => e.role === "user");
                            if (!opener)
                                return "";
                            const t = opener.text.replace(/\s+/g, " ").trim();
                            return `opened with: ${t.length > 160 ? t.slice(0, 160) + "…" : t}`;
                        }
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    Text {
                        visible: root.selectedSession !== null
                        width: parent.width
                        text: root.previewLoading ? "loading recent messages…" : (root.previewRecent.length > 0 ? "recent messages" : "no messages in this session")
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    // Last few turns, newest at the bottom. Plain text only
                    // and capped in height -- this is a glance-and-recognise
                    // affordance, not a second chat transcript.
                    ListView {
                        visible: root.selectedSession !== null && root.previewRecent.length > 0
                        width: parent.width
                        height: visible ? Math.min(contentHeight, 260) : 0
                        clip: true
                        interactive: contentHeight > height
                        spacing: Theme.spacing.sessionMetaGap
                        model: root.previewRecent

                        delegate: Row {
                            required property var modelData
                            width: ListView.view.width
                            spacing: Theme.spacing.launcherIconLabelGap

                            Text {
                                width: 26
                                text: modelData.role === "user" ? "you" : "qubi"
                                color: modelData.role === "user" ? Theme.color.accentPurple : Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }

                            Text {
                                width: parent.width - 26 - Theme.spacing.launcherIconLabelGap
                                text: modelData.text.replace(/\s+/g, " ").trim()
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                    }

                    Text {
                        visible: SessionsState.loadError !== ""
                        width: parent.width
                        text: SessionsState.loadError
                        wrapMode: Text.Wrap
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        color: Theme.color.accentPurple
                    }

                    Row {
                        visible: root.selectedSession !== null
                        spacing: Theme.spacing.themePillGap

                        Rectangle {
                            width: 120
                            height: Theme.spacing.launcherInputHeight
                            radius: Theme.radius.input
                            color: Theme.color.launcherItemSelectedBg
                            border.width: Theme.spacing.borderHairline
                            border.color: Theme.color.launcherInputBorder

                            Text {
                                anchors.centerIn: parent
                                text: "Resume"
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.resumeSelected()
                            }
                        }

                        // Two-step, because this is an irreversible delete of
                        // real conversation history: the first click arms it,
                        // the second commits. Selecting any other session (or
                        // deleting) disarms it again.
                        Rectangle {
                            readonly property bool armed: root.confirmDeleteId.length > 0 && root.confirmDeleteId === root.selectedSession?.sessionId

                            width: 150
                            height: Theme.spacing.launcherInputHeight
                            radius: Theme.radius.input
                            color: armed ? Theme.color.accentPink : "transparent"
                            border.width: Theme.spacing.borderHairline
                            border.color: armed ? Theme.color.accentPink : Theme.color.launcherInputBorder

                            Text {
                                anchors.centerIn: parent
                                text: parent.armed ? "Click again to delete" : "Delete"
                                color: parent.armed ? Theme.color.fg : Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (parent.armed)
                                        root.deleteSelected();
                                    else
                                        root.confirmDeleteId = root.selectedSession?.sessionId ?? "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
