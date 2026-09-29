import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"

// Per-monitor info, read-only. `hyprctl monitors -j` works from inside
// quickshell; Quickshell.screens is the fallback if it fails.
// Writes would need `hyprctl eval` + `hl.config(...)` (the Lua config backend
// has no `hyprctl keyword`), like Theme.qml's border sync.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property var monitors: []
    property bool usingFallback: false

    function refresh() {
        hyprctlProc.running = false;
        hyprctlProc.running = true;
    }

    Process {
        id: hyprctlProc
        command: ["hyprctl", "monitors", "-j"]
        environment: ({
            "LD_LIBRARY_PATH": ""
        })
        stdout: StdioCollector {
            id: hyprctlOut
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.usingFallback = true;
                root.monitors = Quickshell.screens.map(s => ({
                            name: s.name,
                            description: s.model ?? s.name,
                            width: s.width,
                            height: s.height,
                            refreshRate: 0,
                            scale: 1,
                            x: s.x,
                            y: s.y,
                            focused: false,
                            dpmsStatus: true,
                            activeWorkspace: null
                        }));
                return;
            }
            try {
                root.monitors = JSON.parse(hyprctlOut.text);
                root.usingFallback = false;
            } catch (e) {
                console.warn(`SystemDisplay: failed to parse hyprctl monitors -j: ${e}`);
                root.monitors = [];
            }
        }
    }

    Component.onCompleted: root.refresh()

    Column {
        id: column
        width: parent.width
        spacing: 12

        Row {
            width: parent.width
            Text {
                text: "Display"
                font.bold: true
                font.pixelSize: 16
                color: Theme.color.fg
            }
        }

        Text {
            visible: root.usingFallback
            width: parent.width
            wrapMode: Text.Wrap
            text: "hyprctl unavailable -- showing Quickshell.screens instead (refresh rate/workspace unavailable in this fallback)."
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Repeater {
            model: root.monitors

            delegate: Rectangle {
                id: card
                required property var modelData
                width: column.width
                height: infoCol.implicitHeight + 20
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: card.modelData.focused ? Theme.color.accentPurple : Theme.color.launcherBorder

                Column {
                    id: infoCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 10
                    }
                    spacing: 2

                    Text {
                        text: `${card.modelData.name} — ${card.modelData.description ?? ""}`
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        font.bold: true
                    }
                    Text {
                        text: `${card.modelData.width}×${card.modelData.height} @ ${(card.modelData.refreshRate ?? 0).toFixed ? card.modelData.refreshRate.toFixed(1) : card.modelData.refreshRate}Hz · scale ${card.modelData.scale}× · pos (${card.modelData.x}, ${card.modelData.y})`
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    Text {
                        visible: !!card.modelData.activeWorkspace
                        text: `Workspace ${card.modelData.activeWorkspace ? card.modelData.activeWorkspace.name : ""} · DPMS ${card.modelData.dpmsStatus ? "on" : "off"}`
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                }
            }
        }
    }
}
