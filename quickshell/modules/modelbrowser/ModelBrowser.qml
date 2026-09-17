import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Model browser ("Cookbook") — browse llmfit-ranked Ollama-pullable models
// as a card grid, click a card to pull it via Ollama's REST API with a
// live progress bar. Structural template is Launcher.qml/SessionsPicker.qml
// (centered PanelWindow, Overlay layer, click-outside/Escape close).
//
// Skeleton only — refresh() (running `llmfit recommend --json`, filtering
// to ollama_name !== null) and the actual GridView/card rendering are
// filled in separately; this file establishes the shell so that work is
// an edit to an existing file, not authoring a new one from scratch.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: ModelBrowserState.visible
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

    function refresh() {
        ModelBrowserState.loading = true;
        modelFetchProcess.running = true;
    }

    onVisibleChanged: {
        if (visible)
            root.refresh();
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ModelBrowserState.hide()
    }

    IpcHandler {
        target: "modelbrowser"
        function toggle(): void {
            ModelBrowserState.toggle();
        }
    }

    Process {
        id: modelFetchProcess
        // -n 40: llmfit's own database has a known coverage gap mapping
        // larger/newer models to real Ollama tags (see TODO.md §7) — the
        // bare default query surfaces close to zero ollama_name-tagged
        // candidates. A wider N gives the filter something real to find.
        command: ["llmfit", "recommend", "-n", "40", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    const modelsArray = (parsed.models ?? [])
                        .filter(m => m.ollama_name !== null);
                    ModelBrowserState.models = modelsArray;
                    ModelBrowserState.loading = false;
                } catch (e) {
                    ModelBrowserState.loading = false;
                    ModelBrowserState.models = [];
                    console.warn("Failed to parse model list:", e);
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ModelBrowserState.hide()
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

        Text {
            anchors.centerIn: parent
            visible: (ModelBrowserState.models ?? []).length === 0
            text: ModelBrowserState.loading ? "loading models…" : "no models"
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
        }

        GridView {
            anchors {
                fill: parent
                margins: Theme.spacing.modelbrowserGridPad
            }
            clip: true
            cellWidth: Theme.spacing.modelbrowserCardWidth + Theme.spacing.modelbrowserCardGap
            cellHeight: Theme.spacing.modelbrowserCardHeight + Theme.spacing.modelbrowserCardGap
            model: ModelBrowserState.models

            delegate: Rectangle {
                id: card
                required property var modelData
                width: Theme.spacing.modelbrowserCardWidth
                height: Theme.spacing.modelbrowserCardHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: cardMouse.containsMouse ? 2 : 0
                border.color: Theme.color.accentPurple

                // Live download progress for this card's model, if a pull
                // is currently in flight (see the download-trigger logic
                // added separately — ModelBrowserState.downloadProgress is
                // keyed by ollama_name).
                readonly property var progress: ModelBrowserState.downloadProgress[card.modelData.ollama_name]

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: Theme.spacing.launcherRowInset
                    }
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.modelData.name
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: `${card.modelData.parameter_count} params · ${card.modelData.estimated_tps} tok/s`
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.modelData.fit_label
                        color: Theme.color.accentPurple
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: Theme.spacing.launcherRowInset
                    }
                    visible: card.progress === undefined
                    text: card.modelData.installed ? "installed ✓" : "pull"
                    color: card.modelData.installed ? Theme.color.fg : Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }

                // Live pull progress — replaces the installed/pull label
                // while card.progress is set (see downloadProgress above).
                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: Theme.spacing.launcherRowInset
                    }
                    visible: card.progress !== undefined
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.progress?.status ?? ""
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }

                    Rectangle {
                        width: parent.width
                        height: Theme.spacing.modelbrowserProgressHeight
                        radius: height / 2
                        color: Theme.color.launcherInputBorder

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width * ((card.progress?.percent ?? 0) / 100)
                            radius: parent.radius
                            color: Theme.color.accentPurple
                        }
                    }
                }

                // Ollama's /api/pull streams one NDJSON line per progress
                // update (status/digest/total/completed) — confirmed live
                // in an earlier session against this exact endpoint.
                Process {
                    id: pullProcess
                    command: ["curl", "-N", "-s", "-X", "POST", "http://localhost:11434/api/pull", "-d", `{"model":"${card.modelData.ollama_name}"}`]
                    running: false
                    stdout: SplitParser {
                        onRead: line => {
                            try {
                                const upd = JSON.parse(line);
                                if (upd.status === "success") {
                                    const next = Object.assign({}, ModelBrowserState.downloadProgress);
                                    delete next[card.modelData.ollama_name];
                                    ModelBrowserState.downloadProgress = next;
                                    card.modelData = Object.assign({}, card.modelData, {
                                        installed: true
                                    });
                                    return;
                                }
                                const percent = (upd.completed && upd.total > 0) ? (upd.completed / upd.total) * 100 : 0;
                                ModelBrowserState.downloadProgress = Object.assign({}, ModelBrowserState.downloadProgress, {
                                    [card.modelData.ollama_name]: {
                                        percent: percent,
                                        status: upd.status ?? ""
                                    }
                                });
                            } catch (e) {
                                // Not every line is guaranteed valid JSON — skip silently.
                            }
                        }
                    }
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (card.modelData.installed)
                            return;
                        ModelBrowserState.downloadProgress = Object.assign({}, ModelBrowserState.downloadProgress, {
                            [card.modelData.ollama_name]: {
                                percent: 0,
                                status: "starting"
                            }
                        });
                        pullProcess.running = true;
                    }
                }
            }
        }
    }
}
