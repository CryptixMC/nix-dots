import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"
import "../chat"

// Session-history picker: browse past goose sessions and resume one into
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
    readonly property var selectedSession: (selectedIndex >= 0 && selectedIndex < SessionsState.sessions.length) ? SessionsState.sessions[selectedIndex] : null

    function refresh() {
        SessionsState.loading = true;
        root.selectedIndex = -1;
        GooseAcpSession.listSessions((sessions, error) => {
            SessionsState.loading = false;
            // Newest first, matching the CLI's own default ordering.
            SessionsState.sessions = sessions.slice().sort((a, b) => (b.updatedAt ?? "").localeCompare(a.updatedAt ?? ""));
        });
    }

    function resumeSelected() {
        if (!root.selectedSession)
            return;
        ChatState.clear();
        GooseAcpSession.loadSession(root.selectedSession.sessionId, error => {
            if (!error) {
                SessionsState.hide();
                ChatState.visible = true;
            }
        });
    }

    Connections {
        target: GooseAcpSession
        function onHistoryMessage(role, text) {
            ChatState.appendMessage(role, text);
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

                ListView {
                    id: sessionList
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacing.sessionRowGap
                    model: SessionsState.sessions

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
                            onClicked: root.selectedIndex = row.index
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

                    Rectangle {
                        visible: root.selectedSession !== null
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
                }
            }
        }
    }
}
