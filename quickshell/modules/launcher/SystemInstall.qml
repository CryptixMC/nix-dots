import QtQuick
import "../../theme"

// Sub-tab host for package management: a horizontal pill row (unused
// themePill* tokens from ThemeDefaults -- reserved for exactly this shape,
// never claimed by anything until now) over a Loader. Packages/Installed/
// Flatpak are real; the rest are honest "not built yet" stubs so the whole
// surface reads as planned rather than missing.
//
// searchQuery is threaded in from SystemTab (the launcher's own search box
// doubles as the Packages sub-tab's search field, same convention Files/
// Games already use) -- only the Packages sub-tab actually reads it.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property string searchQuery: ""
    property string activeSubTab: "packages"

    readonly property var subTabs: [
        { id: "packages", label: "Packages", glyphOutline: "\u{F03D9}", glyphFilled: "\u{F03D9}", builtIn: true }, // md-package-variant (no outline twin)
        { id: "installed", label: "Installed", glyphOutline: "\u{F05E1}", glyphFilled: "\u{F05E0}", builtIn: true }, // md-check_circle_outline / md-check_circle
        { id: "flatpak", label: "Flatpak", glyphOutline: "\u{F0839}", glyphFilled: "\u{F0839}", builtIn: true }, // md-cube_outline (no filled twin)
        { id: "generations", label: "Generations", glyphOutline: "\u{F0454}", glyphFilled: "\u{F0454}", builtIn: false }, // md-history
        { id: "modules", label: "Modules", glyphOutline: "\u{F0498}", glyphFilled: "\u{F0498}", builtIn: false }, // md-view_module_outline
        { id: "devshells", label: "Dev Shells", glyphOutline: "\u{F0AA1}", glyphFilled: "\u{F0AA1}", builtIn: false }, // md-flask_outline
        { id: "pending", label: "Pending", glyphOutline: "\u{F0EDA}", glyphFilled: "\u{F0EDA}", builtIn: true }, // md-file_document_edit_outline
        { id: "services-catalog", label: "Services", glyphOutline: "\u{F08BB}", glyphFilled: "\u{F0493}", builtIn: false },
        { id: "fonts", label: "Fonts", glyphOutline: "\u{F0AE4}", glyphFilled: "\u{F0AE4}", builtIn: false }, // md-format_font
        { id: "overlays", label: "Overlays", glyphOutline: "\u{F0335}", glyphFilled: "\u{F0335}", builtIn: false } // md-layers_outline
    ]

    Column {
        id: column
        width: parent.width
        spacing: 12

        Text {
            text: "Install"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
            font.family: Theme.font.family
        }

        Flickable {
            width: parent.width
            height: Theme.spacing.themePillHeight
            contentWidth: pillRow.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: pillRow
                spacing: Theme.spacing.themePillGap

                Repeater {
                    model: root.subTabs

                    delegate: Rectangle {
                        id: pill
                        required property var modelData
                        readonly property bool isActive: root.activeSubTab === modelData.id

                        height: Theme.spacing.themePillHeight
                        radius: Math.min(Theme.radius.tabPill, height / 2)
                        color: isActive ? Theme.color.launcherTabActiveBg : (pillMouse.containsMouse ? ThemeDefaults.alpha(Theme.base16.base02, 0.5) : "transparent")
                        border.width: Theme.spacing.borderHairline
                        border.color: isActive ? Theme.color.accentPurple : "transparent"
                        width: pillContent.implicitWidth + Theme.spacing.themePillPadX * 2

                        Behavior on color {
                            ColorAnimation { duration: Theme.motion.hoverColor.duration }
                        }

                        Row {
                            id: pillContent
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: pill.isActive ? pill.modelData.glyphFilled : pill.modelData.glyphOutline
                                renderType: Text.NativeRendering
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                                // launcherTabActiveFg, not accentPurple --
                                // the active pill's own background IS
                                // launcherTabActiveBg/accentPurple-derived
                                // (theme-dependent, can be a solid fill),
                                // so accentPurple text on top of it can lose
                                // all contrast. launcherTabActiveFg is the
                                // token specifically chosen to contrast
                                // against that background (confirmed live:
                                // the real Launcher.qml tab pills use this
                                // exact pairing; copying accentPurple here
                                // instead produced genuinely invisible text
                                // on the active pill).
                                color: pill.isActive ? Theme.color.launcherTabActiveFg : Theme.color.rightModuleFg
                            }
                            Text {
                                text: pill.modelData.label
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                                color: pill.isActive ? Theme.color.launcherTabActiveFg : Theme.color.fg
                            }
                        }

                        MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeSubTab = pill.modelData.id
                        }
                    }
                }
            }
        }

        Loader {
            width: parent.width
            active: true
            sourceComponent: {
                switch (root.activeSubTab) {
                case "packages":
                    return packagesComp;
                case "installed":
                    return installedComp;
                case "flatpak":
                    return flatpakComp;
                case "pending":
                    return pendingComp;
                default:
                    return stubComp;
                }
            }
        }
    }

    Component {
        id: packagesComp
        InstallPackages {
            searchQuery: root.searchQuery
        }
    }
    Component {
        id: installedComp
        InstallInstalled {}
    }
    Component {
        id: flatpakComp
        InstallFlatpak {}
    }
    Component {
        id: pendingComp
        InstallPending {}
    }
    Component {
        id: stubComp
        Column {
            width: parent.width
            spacing: 6

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: `${(root.subTabs.find(t => t.id === root.activeSubTab) ?? { label: "This" }).label} isn't built yet -- planned, not forgotten.`
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }
    }
}
