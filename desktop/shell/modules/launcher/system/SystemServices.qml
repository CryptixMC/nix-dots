import QtQuick
import Quickshell.Io
import "../../../theme"
import ".."

// A fixed list of system units this repo configures plus all user units.
// Restarts go through JobRunner; system units use `privileged: true` (pkexec).
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
        // No `|| echo unknown`: `systemctl is-active` prints a status even when
        // exiting non-zero, so a fallback would add a duplicate line.
        command: ["bash", "-lc", `for u in ${root.systemUnitNames.join(" ")}; do printf '%s\t%s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null)"; done`]
        stdout: StdioCollector {
            id: systemOut
            onStreamFinished: {
                root.systemUnits = systemOut.text.trim().split("\n").filter(l => l.length > 0).map(l => {
                    const [name, status] = l.split("\t");
                    return {
                        name: name,
                        // `||`, not `??`: a nonexistent unit can yield an empty string.
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

    // System units: JobRunner's pkexec prefix raises the polkit prompt.
    property int _restartJobId: -1

    function restart(unit) {
        const argv = unit.scope === "user" ? ["systemctl", "--user", "restart", unit.name] : ["systemctl", "restart", unit.name];
        root._restartJobId = JobRunner.run(`Restart ${unit.name}`, argv, {
            privileged: unit.scope !== "user"
        });
    }

    // JobRunner has no completion callback; watch `jobs` for this job to
    // leave the running state.
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
                // Use the space contentRow actually has left; a fixed offset let the
                // status text overlap the Restart button.
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
