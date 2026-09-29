import QtQuick
import Quickshell
import Quickshell.Io
import "../../../theme"
import ".."

// System info and update buttons. Rendered natively rather than via
// fastfetch, which isn't installed.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property string osName: "loading…"
    property string kernel: "loading…"
    property string host: "loading…"
    property string uptime: "loading…"
    property string cpuModel: "loading…"
    property string gpuModel: "loading…"
    property string ramTotal: "loading…"
    property string diskUsage: "loading…"
    property string shellName: "loading…"
    property string packageCount: "loading…"

    function refresh() {
        root.osName = "loading…";
        root.kernel = "loading…";
        root.host = "loading…";
        root.uptime = "loading…";
        root.cpuModel = "loading…";
        root.gpuModel = "loading…";
        root.ramTotal = "loading…";
        root.diskUsage = "loading…";
        root.shellName = "loading…";
        root.packageCount = "loading…";
        sysInfoProc.running = false;
        sysInfoProc.running = true;
    }

    // One tagged ("KEY:value") command instead of many Processes. Tags, not
    // line order: one failing command (e.g. unsupported `uptime -p`) only
    // blanks its own field instead of shifting every field after it.
    Process {
        id: sysInfoProc
        command: ["bash", "-lc", [
            "echo \"OS:$(. /etc/os-release; echo \"$PRETTY_NAME\")\"",
            "echo \"KERNEL:$(uname -r)\"",
            "echo \"HOST:$(hostname)\"",
            "echo \"UPTIME:$(awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); if(d>0) printf \"%dd %dh %dm\", d,h,m; else if(h>0) printf \"%dh %dm\", h,m; else printf \"%dm\", m}' /proc/uptime)\"",
            "echo \"CPU:$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')\"",
            "echo \"GPU:$(lspci 2>/dev/null | grep -i 'vga\\|3d\\|display' | head -1 | cut -d: -f3- | sed 's/^ *//')\"",
            "echo \"RAM:$(awk '/MemTotal/{printf \"%.1f GiB\", $2/1024/1024}' /proc/meminfo)\"",
            "echo \"DISK:$(df -h / --output=used,size,pcent | tail -1 | awk '{print $1\"/\"$2\" (\"$3\")\"}')\"",
            "echo \"SHELL:$(basename \"$SHELL\")\"",
            "echo \"PKGS:$(nix-store -q --requisites /run/current-system 2>/dev/null | wc -l)\""
        ].join("; ")]
        running: true
        stdout: StdioCollector {
            id: sysInfoOut
            onStreamFinished: {
                const map = {};
                for (const line of sysInfoOut.text.trim().split("\n")) {
                    const idx = line.indexOf(":");
                    if (idx < 0)
                        continue;
                    map[line.slice(0, idx)] = line.slice(idx + 1);
                }
                root.osName = map.OS || "unknown";
                root.kernel = map.KERNEL || "unknown";
                root.host = map.HOST || "unknown";
                root.uptime = map.UPTIME || "unknown";
                root.cpuModel = map.CPU || "unknown";
                root.gpuModel = map.GPU || "unknown";
                root.ramTotal = map.RAM || "unknown";
                root.diskUsage = map.DISK || "unknown";
                root.shellName = map.SHELL || "unknown";
                root.packageCount = map.PKGS || "unknown";
            }
        }
    }

    component UpdateButton: Rectangle {
        id: btn
        required property string label
        required property var argv
        property bool privileged: false
        property string cwd: ""
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
            onClicked: {
                JobRunner.run(btn.label, btn.argv, {
                    privileged: btn.privileged,
                    cwd: btn.cwd
                });
                SystemState.activeSection = "jobs";
            }
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 14

        Row {
            width: parent.width
            spacing: 20

            Text {
                // Plain Unicode, not the Nerd Font NixOS glyph, which renders as an
                // empty string (same bug as FilesTree.qml's chevron).
                text: "❄"
                renderType: Text.NativeRendering
                color: Theme.color.accentPurple
                font.pixelSize: 56
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                width: parent.width - 84

                Text {
                    text: root.osName
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    font.bold: true
                }
                Text {
                    text: `${root.host} · ${root.uptime}`
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }
            }
        }

        Rectangle {
            width: parent.width
            height: infoText.implicitHeight + 20
            radius: Theme.radius.input
            color: Theme.color.launcherInputBg
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.launcherBorder

            Text {
                id: infoText
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                text: `Kernel: ${root.kernel}\nCPU: ${root.cpuModel}\nGPU: ${root.gpuModel}\nRAM: ${root.ramTotal}\nDisk (/): ${root.diskUsage}\nShell: ${root.shellName}\nPackages: ${root.packageCount}\nTheme: ${ThemeState.activeThemeName}`
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
        }

        Rectangle {
            width: 90
            height: 26
            radius: Theme.radius.input
            color: refreshMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.launcherBorder

            Text {
                anchors.centerIn: parent
                text: "Refresh"
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
            }
        }

        Text {
            text: "Update"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
        }

        UpdateButton {
            label: "Update NH OS (nh os switch)"
            argv: ["nh", "os", "switch"]
            // Activation needs root, and nh's internal sudo has nowhere to prompt
            // inside a piped Process, so the whole command runs under pkexec.
            // Unverified: confirm on the first real click.
            privileged: true
        }

        UpdateButton {
            label: "Update NH Home (nh home switch)"
            argv: ["nh", "home", "switch"]
            // Per-user operation, no root needed.
            privileged: false
        }

        UpdateButton {
            label: "Update flake inputs (nix flake update)"
            argv: ["nix", "flake", "update"]
            cwd: `${Quickshell.env("HOME")}/nix-dots`
            privileged: false
        }
    }
}
