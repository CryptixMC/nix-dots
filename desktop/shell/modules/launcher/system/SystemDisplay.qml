import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"

// Live monitor layout: drag to arrange, pick mode/scale/rotation, set primary.
// `hyprctl keyword` fails with the Lua config backend, so changes go through
// `hyprctl eval hl.monitor(...)`. They're runtime-only: kanshi and the static
// config win again on hotplug or reload.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property var monitors: []
    property bool usingFallback: false
    property string selectedName: ""

    readonly property var selected: root.monitors.find(m => m.name === root.selectedName) ?? null
    readonly property var scaleOptions: [1, 1.25, 1.5, 2]
    readonly property var rotationLabels: ["0°", "90°", "180°", "270°"]

    function refresh() {
        hyprctlProc.running = false;
        hyprctlProc.running = true;
    }

    // Size in layout coordinates: mode pixels divided by scale, swapped when rotated 90/270.
    function logicalSize(m) {
        const w = Math.round(m.width / m.scale);
        const h = Math.round(m.height / m.scale);
        return (m.transform % 2 === 1) ? {
            w: h,
            h: w
        } : {
            w: w,
            h: h
        };
    }

    function currentMode(m) {
        return `${m.width}x${m.height}@${Number(m.refreshRate).toFixed(2)}`;
    }

    function monitorExpr(m, overrides) {
        const o = Object.assign({
            mode: root.currentMode(m),
            x: m.x,
            y: m.y,
            scale: m.scale,
            transform: m.transform
        }, overrides);
        return `hl.monitor({output = "${m.name}", mode = "${o.mode}", position = "${Math.round(o.x)}x${Math.round(o.y)}", scale = "${o.scale}", transform = ${o.transform}})`;
    }

    function apply(exprs) {
        Quickshell.execDetached(["hyprctl", "eval", exprs.join("\n")]);
        refreshTimer.restart();
    }

    function setMonitor(m, overrides) {
        root.apply([root.monitorExpr(m, overrides)]);
    }

    // Hyprland has no primary flag; anchoring the monitor at 0x0 is what XWayland
    // and most apps treat as primary, so shift the whole layout and focus it.
    function setPrimary(m) {
        const dx = -m.x, dy = -m.y;
        root.apply(root.monitors.map(o => root.monitorExpr(o, {
                x: o.x + dx,
                y: o.y + dy
            })).concat([`hl.dispatch(hl.dsp.focus({ monitor = "${m.name}" }))`]));
    }

    // Moves a dropped monitor flush against the nearest edge of another one,
    // aligning to that edge's start/centre/end when close, and never overlapping.
    function snapPosition(m, nx, ny) {
        const s = root.logicalSize(m);
        const others = root.monitors.filter(o => o.name !== m.name);
        if (others.length === 0)
            return {
                x: m.x,
                y: m.y
            };

        const rects = others.map(o => {
            const os = root.logicalSize(o);
            return {
                x: o.x,
                y: o.y,
                w: os.w,
                h: os.h
            };
        });
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const align = (v, start, len, size) => {
            const targets = [start, start + len - size, start + (len - size) / 2];
            const near = targets.find(t => Math.abs(t - v) < size * 0.15);
            return near !== undefined ? near : v;
        };
        const overlaps = (x, y) => rects.some(r => x < r.x + r.w && x + s.w > r.x && y < r.y + r.h && y + s.h > r.y);

        let best = null;
        for (const r of rects) {
            const ySide = align(clamp(ny, r.y - s.h + 1, r.y + r.h - 1), r.y, r.h, s.h);
            const xSide = align(clamp(nx, r.x - s.w + 1, r.x + r.w - 1), r.x, r.w, s.w);
            const candidates = [
                {
                    x: r.x + r.w,
                    y: ySide
                },
                {
                    x: r.x - s.w,
                    y: ySide
                },
                {
                    x: xSide,
                    y: r.y + r.h
                },
                {
                    x: xSide,
                    y: r.y - s.h
                }
            ];
            for (const c of candidates) {
                if (overlaps(c.x, c.y))
                    continue;
                const d = Math.hypot(c.x - nx, c.y - ny);
                if (!best || d < best.d)
                    best = {
                        x: Math.round(c.x),
                        y: Math.round(c.y),
                        d: d
                    };
            }
        }
        return best ?? {
            x: m.x,
            y: m.y
        };
    }

    Timer {
        id: refreshTimer
        interval: 400
        onTriggered: root.refresh()
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
                            transform: 0,
                            x: s.x,
                            y: s.y,
                            focused: false,
                            dpmsStatus: true,
                            activeWorkspace: null,
                            availableModes: []
                        }));
            } else {
                try {
                    root.monitors = JSON.parse(hyprctlOut.text);
                    root.usingFallback = false;
                } catch (e) {
                    console.warn(`SystemDisplay: failed to parse hyprctl monitors -j: ${e}`);
                    root.monitors = [];
                }
            }
            if (!root.selected && root.monitors.length > 0)
                root.selectedName = (root.monitors.find(m => m.focused) ?? root.monitors[0]).name;
        }
    }

    Component.onCompleted: root.refresh()

    component Chip: Rectangle {
        id: chip
        required property string label
        property bool active: false
        signal activated

        width: chipText.implicitWidth + 20
        height: 24
        radius: Theme.radius.input
        color: chip.active ? ThemeDefaults.alpha(Theme.color.accentPurple, 0.2) : (chipMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent")
        border.width: Theme.spacing.borderHairline
        border.color: chip.active ? Theme.color.accentPurple : Theme.color.launcherBorder

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !root.usingFallback
            onClicked: chip.activated()
        }
    }

    component SectionLabel: Text {
        color: Theme.color.launcherPlaceholderFg
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Text {
            text: "Display"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }

        Text {
            visible: root.usingFallback
            width: parent.width
            wrapMode: Text.Wrap
            text: "hyprctl unavailable -- showing Quickshell.screens read-only."
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        // Layout map: drag a monitor and drop it next to another to rearrange.
        Rectangle {
            id: map
            width: parent.width
            height: 200
            radius: Theme.radius.input
            color: Theme.color.launcherInputBg
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.launcherBorder

            readonly property real pad: 16
            readonly property var bounds: {
                let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                for (const m of root.monitors) {
                    const s = root.logicalSize(m);
                    minX = Math.min(minX, m.x);
                    minY = Math.min(minY, m.y);
                    maxX = Math.max(maxX, m.x + s.w);
                    maxY = Math.max(maxY, m.y + s.h);
                }
                return root.monitors.length ? {
                    x: minX,
                    y: minY,
                    w: maxX - minX,
                    h: maxY - minY
                } : {
                    x: 0,
                    y: 0,
                    w: 1,
                    h: 1
                };
            }
            readonly property real factor: Math.min((width - pad * 2) / bounds.w, (height - pad * 2) / bounds.h)
            readonly property real originX: (width - bounds.w * factor) / 2
            readonly property real originY: (height - bounds.h * factor) / 2

            Repeater {
                model: root.monitors

                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property var size: root.logicalSize(modelData)
                    readonly property bool isSelected: modelData.name === root.selectedName

                    x: map.originX + (modelData.x - map.bounds.x) * map.factor
                    y: map.originY + (modelData.y - map.bounds.y) * map.factor
                    width: size.w * map.factor
                    height: size.h * map.factor
                    z: tileMouse.drag.active ? 2 : (isSelected ? 1 : 0)
                    radius: 4
                    color: isSelected ? ThemeDefaults.alpha(Theme.color.accentPurple, 0.25) : Theme.color.launcherItemSelectedBg
                    border.width: isSelected ? 2 : Theme.spacing.borderHairline
                    border.color: isSelected ? Theme.color.accentPurple : Theme.color.launcherBorder

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.name
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.bold: true
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: tile.modelData.x === 0 && tile.modelData.y === 0
                            text: "primary"
                            color: Theme.color.accentPurple
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall - 2
                        }
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: root.usingFallback ? null : tile
                        onPressed: root.selectedName = tile.modelData.name
                        onReleased: {
                            const nx = (tile.x - map.originX) / map.factor + map.bounds.x;
                            const ny = (tile.y - map.originY) / map.factor + map.bounds.y;
                            // A plain click only selects.
                            if (Math.abs(nx - tile.modelData.x) < 1 && Math.abs(ny - tile.modelData.y) < 1)
                                return;
                            const p = root.snapPosition(tile.modelData, nx, ny);
                            root.setMonitor(tile.modelData, p);
                        }
                    }
                }
            }
        }

        // Controls for the selected monitor.
        Column {
            width: parent.width
            spacing: 8
            visible: !!root.selected

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.selected ? `${root.selected.name} — ${root.selected.description ?? ""}` : ""
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                font.bold: true
            }
            Text {
                text: root.selected ? `${root.selected.width}×${root.selected.height} @ ${Number(root.selected.refreshRate).toFixed(1)}Hz · scale ${root.selected.scale}× · pos (${root.selected.x}, ${root.selected.y})` : ""
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            SectionLabel {
                text: "Mode"
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: root.selected ? root.selected.availableModes ?? [] : []
                    delegate: Chip {
                        required property string modelData
                        readonly property string mode: modelData.replace("Hz", "")
                        readonly property var parts: mode.split(/[x@]/).map(Number)
                        label: modelData
                        active: root.selected && parts[0] === root.selected.width && parts[1] === root.selected.height && Math.abs(parts[2] - root.selected.refreshRate) < 0.05
                        onActivated: root.setMonitor(root.selected, {
                            mode: mode
                        })
                    }
                }
            }

            SectionLabel {
                text: "Scale"
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: root.scaleOptions
                    delegate: Chip {
                        required property real modelData
                        label: `${modelData}×`
                        active: root.selected && Math.abs(root.selected.scale - modelData) < 0.01
                        onActivated: root.setMonitor(root.selected, {
                            scale: modelData
                        })
                    }
                }
            }

            SectionLabel {
                text: "Rotation"
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: 4
                    delegate: Chip {
                        required property int index
                        label: root.rotationLabels[index]
                        active: root.selected && (root.selected.transform % 4) === index
                        onActivated: root.setMonitor(root.selected, {
                            transform: index
                        })
                    }
                }
            }

            Row {
                spacing: 6
                topPadding: 4
                Chip {
                    label: "Set as primary"
                    active: root.selected && root.selected.x === 0 && root.selected.y === 0
                    onActivated: root.setPrimary(root.selected)
                }
                Chip {
                    label: "Refresh"
                    onActivated: root.refresh()
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Changes apply live and last until the next hotplug or Hyprland reload."
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall - 1
            }
        }
    }
}
