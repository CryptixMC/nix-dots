import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"

// Left column: system status (real, gathered live -- see sysInfo below,
// replacing the earlier hardcoded "Ubuntu 22.04 / Quad-Core" placeholder
// text that never reflected this actual NixOS/i7-1260P machine) + update
// buttons. Right column: themes, moved here as a section per Liam's own
// explicit correction (real quote, sessions.db transcript): "I want the
// theme tab to be located as a section within system and not its own
// tab." Theme picks now render as real preview images (ThemeLoader.themes
// exposes each theme's own wallpaper.dir/.image without switching to it),
// not the old plain-text pills -- the other explicit ask from the same
// message ("instead of just text they should display an image of what
// the theme looks like").
//
// Update buttons launch in a real terminal (ghostty -e), not a hidden
// background Process -- `nh os switch` needs root and Quickshell's own
// Process has no pty, so a silent background run would just hang forever
// at an unanswerable sudo password prompt. Same "wrap in ghostty -e"
// pattern Launcher.qml already uses for runInTerminal desktop entries.
Item {
    id: root
    width: parent.width
    height: Math.max(leftColumn.implicitHeight, rightColumn.implicitHeight)

    function runInTerminal(command) {
        Quickshell.execDetached({
            command: ["ghostty", "-e", "bash", "-lc", command]
        });
    }

    Process {
        id: sysInfoProc
        // One combined command (not four separate Processes) so the four
        // fields land in a single ordered stdout read -- simpler than
        // coordinating onStreamFinished across four independent
        // Process/StdioCollector pairs for what's fundamentally one
        // snapshot of "the current system state".
        command: ["bash", "-lc", "grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2; uname -r; grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//'; awk '/MemTotal/{printf \"%.1f GiB\\n\", $2/1024/1024}' /proc/meminfo"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.osName = lines[0] ?? "unknown";
                root.kernel = lines[1] ?? "unknown";
                root.cpuModel = lines[2] ?? "unknown";
                root.ramTotal = lines[3] ?? "unknown";
            }
        }
    }

    property string osName: "loading…"
    property string kernel: "loading…"
    property string cpuModel: "loading…"
    property string ramTotal: "loading…"

    Row {
        anchors.fill: parent
        spacing: Theme.spacing.themeRowGap * 2

        Column {
            id: leftColumn
            width: (root.width - Theme.spacing.themeRowGap * 2) / 2
            spacing: 12

            Text {
                text: "System"
                font.bold: true
                font.pixelSize: 16
                color: Theme.color.fg
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
                    text: `OS: ${root.osName}\nKernel: ${root.kernel}\nCPU: ${root.cpuModel}\nRAM: ${root.ramTotal}`
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }

            Text {
                text: "Update"
                font.bold: true
                font.pixelSize: 14
                color: Theme.color.fg
            }

            component UpdateButton: Rectangle {
                id: btn
                required property string label
                required property string command
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
                    // Opens a real terminal instead of running silently --
                    // `nh os switch` needs a real sudo prompt and can take
                    // minutes; a hidden Process gives no way to see either.
                    onClicked: root.runInTerminal(btn.command)
                }
            }

            UpdateButton {
                label: "Update NH OS (nh os switch)"
                command: "nh os switch; echo; echo '[done, press enter to close]'; read"
            }

            UpdateButton {
                label: "Update NH Home (nh home switch)"
                command: "nh home switch; echo; echo '[done, press enter to close]'; read"
            }

            UpdateButton {
                label: "Update flake inputs (nix flake update)"
                command: "cd ~/nix-dots && nix flake update; echo; echo '[done, press enter to close]'; read"
            }
        }

        Column {
            id: rightColumn
            width: (root.width - Theme.spacing.themeRowGap * 2) / 2
            spacing: Theme.spacing.themeRowGap

            Text {
                text: "Themes"
                font.bold: true
                font.pixelSize: 16
                color: Theme.color.fg
            }

            Flow {
                width: parent.width
                spacing: Theme.spacing.themeWallpaperGap

                Repeater {
                    model: ThemeLoader.discoveredThemeNames

                    delegate: Rectangle {
                        id: card
                        required property string modelData
                        readonly property var themeData: ThemeLoader.themes[modelData]
                        readonly property bool isActive: ThemeState.activeThemeName === modelData

                        width: Theme.spacing.themeWallpaperThumbWidth
                        height: Theme.spacing.themeWallpaperThumbHeight + 22
                        radius: Theme.radius.input
                        color: "transparent"

                        Rectangle {
                            id: thumbFrame
                            width: parent.width
                            height: Theme.spacing.themeWallpaperThumbHeight
                            radius: Theme.radius.input
                            color: Theme.color.launcherInputBg
                            border.width: card.isActive ? 2 : Theme.spacing.borderHairline
                            border.color: card.isActive ? Theme.color.accentPurple : (cardMouse.containsMouse ? Theme.color.purpleHover : Theme.color.launcherBorder)
                            clip: true

                            Behavior on border.color {
                                ColorAnimation { duration: Theme.motion.hoverColor.duration }
                            }

                            // Real preview image, not text -- ThemeLoader.
                            // themes[name] carries that theme's OWN
                            // wallpaper.dir/.image (via ThemeDefaults.build,
                            // same shape Theme.wallpaper exposes for the
                            // active theme) without needing to switch to it
                            // first, so every theme's card shows its actual
                            // default wallpaper.
                            Image {
                                anchors.fill: parent
                                anchors.margins: thumbFrame.border.width
                                visible: card.themeData?.wallpaper?.image
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                source: card.themeData?.wallpaper?.image ? `file://${card.themeData.wallpaper.dir}/${card.themeData.wallpaper.image}` : ""
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !card.themeData?.wallpaper?.image
                                text: "no preview"
                                color: Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }

                        Text {
                            anchors {
                                top: thumbFrame.bottom
                                left: parent.left
                                right: parent.right
                                topMargin: 4
                            }
                            horizontalAlignment: Text.AlignHCenter
                            text: card.modelData
                            color: card.isActive ? Theme.color.accentPurple : Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.capitalization: Font.Capitalize
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ThemeState.setTheme(card.modelData)
                        }
                    }
                }
            }

            // Active theme's own wallpaper-file picker -- unchanged from
            // the old standalone ThemesTab.qml, just relocated here.
            Text {
                text: "Wallpaper (active theme)"
                font.bold: true
                font.pixelSize: 14
                color: Theme.color.fg
                visible: Theme.wallpaper.available.length > 0
            }

            Flow {
                width: parent.width
                spacing: Theme.spacing.themeWallpaperGap
                visible: Theme.wallpaper.available.length > 0

                Repeater {
                    model: Theme.wallpaper.available

                    delegate: Rectangle {
                        id: wthumb
                        required property string modelData
                        readonly property bool isActive: (Theme.wallpaper.engine === "static" && Theme.wallpaper.image === modelData) || (Theme.wallpaper.engine === "gif" && Theme.wallpaper.gif === modelData)

                        width: Theme.spacing.themeWallpaperThumbWidth
                        height: Theme.spacing.themeWallpaperThumbHeight
                        radius: Theme.radius.input
                        color: "transparent"
                        border.width: isActive ? 2 : Theme.spacing.borderHairline
                        border.color: isActive ? Theme.color.accentPurple : (wthumbMouse.containsMouse ? Theme.color.purpleHover : Theme.color.launcherBorder)
                        clip: true

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.motion.hoverColor.duration }
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: parent.border.width
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            source: `file://${Theme.wallpaper.dir}/${wthumb.modelData}`
                        }

                        MouseArea {
                            id: wthumbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ThemeState.setWallpaperOverride(ThemeState.activeThemeName, wthumb.modelData)
                        }
                    }
                }
            }
        }
    }
}
