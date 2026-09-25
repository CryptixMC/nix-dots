import QtQuick
import Quickshell.Io
import "../../theme"

// System/home-manager generations plus disk usage and the cleanup
// commands. `nix-env --list-generations -p /nix/var/nix/profiles/system`
// needs a lock file NixOS itself doesn't grant plain users write access to
// (confirmed live: "Permission denied" on the lock file even for a read-
// only list) -- `ls` on the profile directory's own generation symlinks
// gives the same information without that lock. `home-manager generations`
// has no such restriction and is used directly.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property var systemGenerations: []
    property var homeGenerations: []
    property string diskUsage: "loading…"

    function refresh() {
        genProc.running = false;
        genProc.running = true;
    }

    Process {
        id: genProc
        command: ["bash", "-lc", [
            "ls -la /nix/var/nix/profiles/ | grep -oE 'system-[0-9]+-link -> .*nixos-system-[a-zA-Z0-9]+-[0-9.]+' | tail -8",
            "echo '###SEP###'",
            "home-manager generations 2>/dev/null | head -8",
            "echo '###SEP###'",
            "df -h /nix --output=used,size,pcent | tail -1"
        ].join("; ")]
        stdout: StdioCollector {
            id: genOut
            onStreamFinished: {
                const parts = genOut.text.split("###SEP###");
                root.systemGenerations = (parts[0] ?? "").trim().split("\n").filter(l => l.length > 0).reverse();
                root.homeGenerations = (parts[1] ?? "").trim().split("\n").filter(l => l.length > 0);
                root.diskUsage = (parts[2] ?? "").trim();
            }
        }
    }

    Component.onCompleted: root.refresh()

    component MaintButton: Rectangle {
        id: btn
        required property string label
        required property var argv
        width: parent.width
        height: Theme.spacing.launcherRowHeight
        radius: Theme.radius.input
        color: mouse.containsMouse ? Theme.color.launcherItemSelectedBg : Theme.color.launcherInputBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.accentPurple

        Behavior on color {
            ColorAnimation { duration: Theme.motion.hoverColor.duration }
        }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Not privileged -- all three of these are store/GC operations,
            // which a normal user already proxies through the multi-user
            // nix-daemon (no sudo needed today, confirmed by the original
            // runInTerminal commands never prefixing `sudo` either). That's
            // different from SystemAbout's "nh os switch", whose system
            // ACTIVATION step is outside the daemon's own privilege proxy
            // and genuinely needs root.
            onClicked: {
                JobRunner.run(btn.label, btn.argv, {
                    privileged: false
                });
                SystemState.activeSection = "jobs";
            }
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Text {
            text: "Maintenance"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }

        Rectangle {
            width: parent.width
            height: usageText.implicitHeight + 16
            radius: Theme.radius.input
            color: Theme.color.launcherInputBg
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.launcherBorder

            Text {
                id: usageText
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 8
                }
                text: `/nix usage: ${root.diskUsage}`
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }

        Text {
            text: "System generations (recent)"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
        }
        Repeater {
            model: root.systemGenerations
            delegate: Text {
                required property string modelData
                width: column.width
                elide: Text.ElideRight
                text: modelData
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }

        Text {
            text: "Home Manager generations (recent)"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
        }
        Repeater {
            model: root.homeGenerations
            delegate: Text {
                required property string modelData
                width: column.width
                elide: Text.ElideRight
                text: modelData
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }

        Text {
            text: "Cleanup"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
        }

        MaintButton {
            label: "nh clean all"
            argv: ["nh", "clean", "all"]
        }
        MaintButton {
            label: "nix-collect-garbage -d"
            argv: ["nix-collect-garbage", "-d"]
        }
        MaintButton {
            label: "nix store optimise"
            argv: ["nix", "store", "optimise"]
        }
    }
}
