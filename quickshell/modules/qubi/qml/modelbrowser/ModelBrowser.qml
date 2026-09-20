import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"

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

    // The model actually answering the current conversation right now, so
    // a card/pill for it can render as "in use" rather than merely
    // "installed". Handles both a real named tier (currentTier is e.g.
    // "light") and an ad hoc qubi/use_model pick (currentTier is
    // "model:<tag>" -- see qubi_engine.py's Session.tier_sessions header
    // comment for why that synthetic naming exists).
    readonly property string currentModelName: GooseAcpSession.currentTier.startsWith("model:") ? GooseAcpSession.currentTier.slice("model:".length) : (GooseAcpSession.tierModels[GooseAcpSession.currentTier] ?? "")

    // One grid, not two lists. Earlier this drew installed models as a
    // separate horizontal pill strip above the llmfit recommendation grid;
    // the two were structurally different (different fields, different
    // interaction) which is exactly what made it confusing to scan. This
    // normalizes both sources into one shape and sorts installed first, so
    // "what do I already have" and "what could I get" read as one list with
    // a visual badge, not two unrelated widgets.
    //
    // llmfit's own `installed` flag can lag the real Ollama state (it's
    // filled in once when the recommendation feed loads, and only patched
    // locally after a pull completes THIS session) -- recomputed against
    // the live installedModels() result instead of trusted as-is.
    function _mergeModels(llmfitList, installedList) {
        const installedNames = new Set((installedList ?? []).map(m => m.name));
        const fromFeed = (llmfitList ?? []).map(m => ({
            ollama_name: m.ollama_name,
            name: m.name,
            parameter_count: m.parameter_count,
            estimated_tps: m.estimated_tps,
            fit_label: m.fit_label,
            installed: installedNames.has(m.ollama_name) || m.installed === true
        }));
        const feedNames = new Set(fromFeed.map(m => m.ollama_name));
        const extra = (installedList ?? [])
            .filter(m => !feedNames.has(m.name))
            .map(m => ({
                ollama_name: m.name,
                name: m.name,
                parameter_count: m.parameterSize || "?",
                estimated_tps: "?",
                fit_label: "already on this machine",
                installed: true
            }));
        const merged = fromFeed.concat(extra);
        // Stable sort (spec-guaranteed in the JS engines Qt Quick embeds):
        // installed cards float to the top, relative order otherwise
        // unchanged within each group.
        merged.sort((a, b) => (b.installed ? 1 : 0) - (a.installed ? 1 : 0));
        return merged;
    }

    readonly property var mergedModels: root._mergeModels(ModelBrowserState.models, ModelBrowserState.installed)

    function refresh() {
        ModelBrowserState.loading = true;
        modelFetchProcess.running = true;
        root.refreshInstalled();
    }

    function refreshInstalled() {
        ModelBrowserState.installedLoading = true;
        GooseAcpSession.installedModels(models => {
            ModelBrowserState.installedLoading = false;
            ModelBrowserState.installed = models;
        });
    }

    // Use an installed model for the current conversation right now. No-op
    // when opened standalone (useMode false): browsing must never silently
    // change what the chat panel is doing underneath it.
    function useModel(name) {
        if (!ModelBrowserState.useMode || name.length === 0)
            return;
        GooseAcpSession.useModelNow(name, error => {
            if (!error)
                ModelBrowserState.hideAndReset();
        });
    }

    onVisibleChanged: {
        if (visible)
            root.refresh();
        else
            ModelBrowserState.useMode = false;
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ModelBrowserState.hideAndReset()
    }

    IpcHandler {
        target: "modelbrowser"
        function toggle(): void {
            // The external/keybind entry point is always standalone
            // browsing -- useMode is only ever turned on from inside the
            // chat panel itself (tier picker / hamburger menu).
            ModelBrowserState.useMode = false;
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
        // Clears useMode too: dismissing without choosing must not leave
        // the browser armed to "use now" the next time it is opened
        // standalone.
        onClicked: ModelBrowserState.hideAndReset()
    }

    Rectangle {
        id: box
        anchors.centerIn: parent
        width: QubiTheme.spacing.launcherWidthWide
        height: Math.min(parent.height * 0.75, 720)
        radius: QubiTheme.radius.panel
        color: QubiTheme.color.launcherBg
        border.width: QubiTheme.spacing.borderHairline
        border.color: QubiTheme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
        }

        // Header: what this panel is, and — when opened from the chat
        // panel's "use a model now" entry points — how a click behaves.
        // Without that second line the same grid would mean two different
        // things depending on how it was opened.
        Item {
            id: browserHeader
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: QubiTheme.spacing.modelbrowserGridPad
            }
            height: QubiTheme.spacing.chatHeaderHeight

            Text {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: QubiTheme.spacing.launcherRowInset
                }
                text: ModelBrowserState.useMode ? "Use a model for this conversation" : "Models"
                color: QubiTheme.color.fg
                font.family: QubiTheme.font.family
                font.pixelSize: QubiTheme.font.sizeBase
                font.bold: true
            }

            Text {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    rightMargin: QubiTheme.spacing.launcherRowInset
                }
                text: {
                    if (!ModelBrowserState.useMode)
                        return "click a card to install";
                    return ModelBrowserState.installedLoading ? "loading installed models…" : "click an installed model to use it now";
                }
                color: QubiTheme.color.launcherPlaceholderFg
                font.family: QubiTheme.font.family
                font.pixelSize: QubiTheme.font.sizeSmall
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.mergedModels.length === 0
            text: ModelBrowserState.loading ? "loading models…" : "no models"
            color: QubiTheme.color.launcherPlaceholderFg
            font.family: QubiTheme.font.family
            font.pixelSize: QubiTheme.font.sizeBase
        }

        GridView {
            anchors {
                top: browserHeader.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: QubiTheme.spacing.modelbrowserGridPad
            }
            clip: true
            cellWidth: QubiTheme.spacing.modelbrowserCardWidth + QubiTheme.spacing.modelbrowserCardGap
            cellHeight: QubiTheme.spacing.modelbrowserCardHeight + QubiTheme.spacing.modelbrowserCardGap
            model: root.mergedModels

            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool isCurrent: card.modelData.ollama_name === root.currentModelName
                width: QubiTheme.spacing.modelbrowserCardWidth
                height: QubiTheme.spacing.modelbrowserCardHeight
                radius: QubiTheme.radius.input
                color: QubiTheme.color.launcherInputBg
                border.width: cardMouse.containsMouse ? 2 : (card.isCurrent ? 1 : 0)
                border.color: QubiTheme.color.accentPurple

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
                        margins: QubiTheme.spacing.launcherRowInset
                    }
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.modelData.name
                        color: QubiTheme.color.fg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeSmall
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: `${card.modelData.parameter_count} params · ${card.modelData.estimated_tps} tok/s`
                        color: QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeSmall
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.modelData.fit_label
                        color: QubiTheme.color.accentPurple
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeSmall
                    }
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: QubiTheme.spacing.launcherRowInset
                    }
                    visible: card.progress === undefined
                    text: card.isCurrent ? "in use ✓" : (card.modelData.installed ? "installed ✓" : "pull")
                    color: card.modelData.installed ? QubiTheme.color.accentPurple : QubiTheme.color.launcherPlaceholderFg
                    font.family: QubiTheme.font.family
                    font.pixelSize: QubiTheme.font.sizeSmall
                }

                // Live pull progress — replaces the installed/pull label
                // while card.progress is set (see downloadProgress above).
                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        margins: QubiTheme.spacing.launcherRowInset
                    }
                    visible: card.progress !== undefined
                    spacing: 2

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.progress?.status ?? ""
                        color: QubiTheme.color.launcherPlaceholderFg
                        font.family: QubiTheme.font.family
                        font.pixelSize: QubiTheme.font.sizeSmall
                    }

                    Rectangle {
                        width: parent.width
                        height: QubiTheme.spacing.modelbrowserProgressHeight
                        radius: height / 2
                        color: QubiTheme.color.launcherInputBorder

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width * ((card.progress?.percent ?? 0) / 100)
                            radius: parent.radius
                            color: QubiTheme.color.accentPurple
                        }
                    }
                }

                // Ollama's /api/pull streams one NDJSON line per progress
                // update (status/digest/total/completed) — confirmed live
                // in an earlier session against this exact endpoint.
                Process {
                    id: pullProcess
                    command: ["curl", "-N", "-s", "-X", "POST", `${QubiConfig.ollamaUrl}/api/pull`, "-d", `{"model":"${card.modelData.ollama_name}"}`]
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
                        if (card.modelData.installed) {
                            root.useModel(card.modelData.ollama_name);
                            return;
                        }
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
