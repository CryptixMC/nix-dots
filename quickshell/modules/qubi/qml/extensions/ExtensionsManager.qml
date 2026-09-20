import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"

// Extensions/MCP manager — list config.yaml's registered extensions,
// toggle enabled/disabled, add a new stdio MCP server through a form.
// Structural template is SessionsPicker.qml (centered PanelWindow,
// Overlay layer, click-outside/Escape close, list on the left).
//
// Reading config.yaml now lives in ExtensionsState (so the chat panel's
// MCP indicator can show a count without this overlay ever being
// opened); this file just renders and writes. Writes go through
// `yq -i`, the same mechanism qubi-state-sync already uses for other
// config.yaml fields — config.yaml itself stays the single source of
// truth, this UI is just a friendlier way to edit it than hand-editing
// YAML.
PanelWindow {
    id: root

    readonly property string configPath: QubiConfig.gooseConfigPath

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
        ExtensionsState.refresh();
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
        width: QubiTheme.spacing.launcherWidthWide
        height: Math.min(parent.height * 0.75, 720)
        radius: QubiTheme.radius.panel
        color: QubiTheme.color.launcherBg
        border.width: QubiTheme.spacing.borderHairline
        border.color: QubiTheme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
        }

        Column {
            anchors {
                fill: parent
                margins: QubiTheme.spacing.launcherContentInset
            }
            spacing: QubiTheme.spacing.launcherContentGap

            Text {
                text: ExtensionsState.loading ? "loading extensions…" : `${ExtensionsState.extensions.length} extensions`
                color: QubiTheme.color.launcherPlaceholderFg
                font.family: QubiTheme.font.family
                font.pixelSize: QubiTheme.font.sizeSmall
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
                    radius: QubiTheme.radius.input
                    color: QubiTheme.color.launcherInputBg

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: QubiTheme.spacing.launcherRowInset
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            text: modelData.display_name
                            color: QubiTheme.color.fg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeSmall
                        }

                        Text {
                            text: modelData.type
                            color: QubiTheme.color.launcherPlaceholderFg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeSmall
                        }

                        Text {
                            text: modelData.enabled ? "enabled" : "disabled"
                            color: modelData.enabled ? QubiTheme.color.accentPurple : QubiTheme.color.launcherPlaceholderFg
                            font.family: QubiTheme.font.family
                            font.pixelSize: QubiTheme.font.sizeSmall
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
