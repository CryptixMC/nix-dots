import QtQuick
import Quickshell.Io
import "../../theme"

// A fixed list of system units this repo actually cares about (egpu-eject,
// greetd, fprintd, bluetooth, NetworkManager -- all named directly in
// modules/nixos/*, not discovered) plus whatever's in `systemctl --user
// list-units`. Restart routes through JobRunner for both scopes -- user
// units need no privilege, system units get `privileged: true` (pkexec,
// not a `sudo` shelled into a terminal), so a themed prompt appears instead
// of a Ghostty window.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    readonly property var systemUnitNames: ["egpu-eject.service", "greetd.service", "fprintd.service", "bluetooth.service", "NetworkManager.service"]

    property var systemUnits: []
    property var userUnits: []

    function refresh() {
        systemProc.running = false;
        systemProc.running = true;
        userProc.running = false;
        userProc.running = true;
    }

    Process {
        id: systemProc
        // No `|| echo unknown` fallback -- `systemctl is-active` always
        // prints a real status word to stdout ("inactive", "failed", ...)
        // even when it exits non-zero (confirmed live: inactive units exit
        // 3 but still print "inactive"). The fallback used to fire on top
        // of that real output instead of replacing it, splicing a second
        // "unknown\tunknown" line into the capture for every non-active
        // unit -- three phantom rows, one per inactive unit, confirmed via
        // a live screenshot.
        command: ["bash", "-lc", `for u in ${root.systemUnitNames.join(" ")}; do printf '%s\t%s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null)"; done`]
        stdout: StdioCollector {
            id: systemOut
            onStreamFinished: {
                root.systemUnits = systemOut.text.trim().split("\n").filter(l => l.length > 0).map(l => {
                    const [name, status] = l.split("\t");
                    return {
                        name: name,
                        // `||`, not `??` -- a genuinely nonexistent unit's
                        // is-active call can capture as an empty string
                        // rather than undefined, which `??` lets straight
                        // through as a blank status label.
                        status: status || "unknown",
                        scope: "system"
                    };
                });
            }
        }
    }

    Process {
        id: userProc
        command: ["bash", "-lc", "systemctl --user list-units --type=service --no-legend --no-pager | awk '{print $1\"\\t\"$4}'"]
        stdout: StdioCollector {
            id: userOut
            onStreamFinished: {
                root.userUnits = userOut.text.trim().split("\n").filter(l => l.length > 0).map(l => {
                    const [name, status] = l.split("\t");
                    return {
                        name: name,
                        status: status || "unknown",
                        scope: "user"
                    };
                }).slice(0, 20);
            }
        }
    }

    Component.onCompleted: root.refresh()

    // Both scopes now go through JobRunner -- system units no longer get
    // a `sudo` shelled into a terminal; plain `systemctl restart` asks
    // polkit directly (JobRunner's `privileged: true` prefixes pkexec,
    // which is what actually raises the auth prompt), so there's no `sudo`
    // in the command at all anymore.
    property int _restartJobId: -1

    function restart(unit) {
        const argv = unit.scope === "user" ? ["systemctl", "--user", "restart", unit.name] : ["systemctl", "restart", unit.name];
        root._restartJobId = JobRunner.run(`Restart ${unit.name}`, argv, {
            privileged: unit.scope !== "user"
        });
    }

    // JobRunner has no per-job completion callback -- watch the shared
    // `jobs` array for this specific job leaving the "running" state, same
    // pattern any other JobRunner consumer needing a "refresh after" hook
    // should follow.
    Connections {
        target: JobRunner
        function onJobsChanged() {
            if (root._restartJobId < 0)
                return;
            const job = JobRunner.jobById(root._restartJobId);
            if (job && job.state !== "running") {
                root._restartJobId = -1;
                root.refresh();
            }
        }
    }

    component UnitRow: Rectangle {
        id: row
        required property var unit
        width: parent.width
        height: 30
        radius: Theme.radius.input
        color: rowMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

        Row {
            id: contentRow
            anchors {
                left: parent.left
                right: restartBtn.left
                leftMargin: 8
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            spacing: 8

            Rectangle {
                id: dot
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: row.unit.status === "active" ? Theme.color.accentPurple : Theme.color.moduleDisabledFg
            }
            Text {
                text: row.unit.name
                elide: Text.ElideRight
                // Reserves exactly the space contentRow actually has left
                // over, not a magic-number guess against the OUTER row's
                // full width -- that guess (`row.width - 140`) undercounted
                // the real overhead (restart button + margins + the status
                // label's own width), so status text spilled out past the
                // Row's right edge and visibly overlapped the Restart
                // button (confirmed live: "inactiveRestart" rendered as
                // one smashed-together string).
                width: contentRow.width - dot.width - statusLabel.implicitWidth - contentRow.spacing * 2
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
            Text {
                id: statusLabel
                text: row.unit.status
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }

        Rectangle {
            id: restartBtn
            anchors {
                right: parent.right
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            width: 60
            height: 22
            radius: Theme.radius.input
            color: restartMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.launcherBorder

            Text {
                anchors.centerIn: parent
                text: "Restart"
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall - 1
            }
            MouseArea {
                id: restartMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.restart(row.unit)
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            z: -1
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 10

        Text {
            text: "Services"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }

        Text {
            text: "System"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
        }
        Repeater {
            model: root.systemUnits
            delegate: UnitRow {
                required property var modelData
                width: column.width
                unit: modelData
            }
        }

        Text {
            text: "User"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
        }
        Repeater {
            model: root.userUnits
            delegate: UnitRow {
                required property var modelData
                width: column.width
                unit: modelData
            }
        }
    }
}
