import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme"

// Extensions/MCP manager — list config.yaml's registered extensions,
// toggle enabled/disabled, add a new stdio MCP server through a form.
// Structural template is SessionsPicker.qml (centered PanelWindow,
// Overlay layer, click-outside/Escape close, list on the left).
//
// Reads config.yaml directly (it's valid JSON despite the .yaml
// extension — lib.generators.toYAML's flow-style output for this shape
// happens to be JSON-compatible, confirmed live). Writes go through
// `yq -i`, the same mechanism goose-state-sync already uses for other
// config.yaml fields — config.yaml itself stays the single source of
// truth, this UI is just a friendlier way to edit it than hand-editing
// YAML.
PanelWindow {
    id: root

    readonly property string configPath: `${Quickshell.env("HOME")}/.config/goose/config.yaml`

    screen: Quickshell.screens[0] ?? null
    visible: ExtensionsState.visible
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
        ExtensionsState.loading = true;
        readProcess.running = true;
    }

    function toggleExtension(key, currentlyEnabled) {
        toggleProcess.command = ["yq", "-i", `.extensions.${key}.enabled = ${!currentlyEnabled}`, root.configPath];
        toggleProcess.running = true;
    }

    onVisibleChanged: {
        if (visible)
            root.refresh();
    }

    Shortcut {
        sequence: "Escape"
        onActivated: ExtensionsState.hide()
    }

    IpcHandler {
        target: "extensions"
        function toggle(): void {
            ExtensionsState.toggle();
        }
    }

    Process {
        id: readProcess
        command: ["cat", root.configPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    const extObj = parsed.extensions ?? {};
                    ExtensionsState.extensions = Object.keys(extObj).sort().map(key => {
                        const e = extObj[key];
                        return {
                            key: key,
                            name: e.name ?? key,
                            display_name: e.display_name ?? e.name ?? key,
                            type: e.type ?? "",
                            enabled: e.enabled === true,
                            description: e.description ?? "",
                            cmd: e.cmd ?? ""
                        };
                    });
                    ExtensionsState.loading = false;
                } catch (e) {
                    ExtensionsState.loading = false;
                    ExtensionsState.extensions = [];
                    console.warn("Failed to parse config.yaml:", e);
                }
            }
        }
    }

    // Fire-and-forget: re-reads the file afterward regardless of exit
    // code (yq's own error output is enough of a signal if something's
    // wrong — a real "did it work" check happens by refreshing and
    // seeing whether the value actually changed).
    Process {
        id: toggleProcess
        running: false
        onExited: root.refresh()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ExtensionsState.hide()
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

        Column {
            anchors {
                fill: parent
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap

            Text {
                text: ExtensionsState.loading ? "loading extensions…" : `${ExtensionsState.extensions.length} extensions`
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            ListView {
                width: parent.width
                height: 400
                clip: true
                spacing: 4
                model: ExtensionsState.extensions
                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 40
                    radius: Theme.radius.input
                    color: Theme.color.launcherInputBg

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing.launcherRowInset
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: modelData.display_name
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        Text {
                            text: modelData.type
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        Text {
                            text: modelData.enabled ? "enabled" : "disabled"
                            color: modelData.enabled ? Theme.color.accentPurple : Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleExtension(modelData.key, modelData.enabled)
                    }
                }
            }
        }
    }
}
