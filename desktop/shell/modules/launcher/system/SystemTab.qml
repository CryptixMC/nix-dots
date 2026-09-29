import QtQuick
import "../../../theme"

// Left-nav sectioned panel: SystemState.sections on the left, the active
// section's component on the right. Wrapped in a Flickable with the same
// computedHeight clamp GamesTab/FilesTab use so content can't overflow.
Item {
    id: root
    width: parent.width
    readonly property real computedHeight: Math.min(inner.implicitHeight, Theme.spacing.launcherTabBodyMaxHeight)
    height: root.computedHeight
    implicitHeight: root.computedHeight

    property string searchQuery: ""

    // Exposed read-only for IPC debug hooks; internal code uses callSection().
    readonly property alias contentLoader: contentLoader

    // "nav" | "content": which side owns arrow keys, like FilesTab's tree/grid
    // split. Left from nav and Right at content's end cross tabs.
    property string focusZone: "nav"

    function callSection(fnName, fallback) {
        const item = contentLoader.item;
        if (item && typeof item[fnName] === "function")
            return item[fnName]();
        return fallback;
    }

    function moveUp() {
        if (root.focusZone === "nav") {
            const idx = SystemState.sectionIndex(SystemState.activeSection);
            if (idx > 0)
                SystemState.activeSection = SystemState.sections[idx - 1].id;
            return true;
        }
        return root.callSection("moveUp", true);
    }

    function moveDown() {
        if (root.focusZone === "nav") {
            const idx = SystemState.sectionIndex(SystemState.activeSection);
            if (idx < SystemState.sections.length - 1)
                SystemState.activeSection = SystemState.sections[idx + 1].id;
            return true;
        }
        return root.callSection("moveDown", true);
    }

    function moveLeft() {
        if (root.focusZone === "content") {
            if (root.callSection("moveLeft", false))
                return true;
            root.focusZone = "nav";
            return true;
        }
        return false;
    }

    function moveRight() {
        if (root.focusZone === "nav") {
            root.focusZone = "content";
            return true;
        }
        return root.callSection("moveRight", false);
    }

    function activate() {
        if (root.focusZone === "nav") {
            root.focusZone = "content";
            return;
        }
        root.callSection("activate", undefined);
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: inner.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: inner
            width: parent.width
            spacing: Theme.spacing.gameSectionGap

            Column {
                id: nav
                width: 150
                spacing: 2

                Repeater {
                    model: SystemState.sections

                    delegate: Rectangle {
                        id: navRow
                        required property var modelData
                        required property int index
                        readonly property bool isActive: SystemState.activeSection === modelData.id

                        width: nav.width
                        height: Theme.spacing.fileTreeRowHeight + 4
                        radius: Theme.radius.input
                        color: navRow.isActive ? Theme.color.launcherItemSelectedBg : (navMouse.containsMouse ? ThemeDefaults.alpha(Theme.base16.base02, 0.5) : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: Theme.motion.hoverColor.duration }
                        }

                        Rectangle {
                            width: Theme.spacing.launcherIndicatorWidth
                            height: parent.height
                            color: navRow.isActive && root.focusZone === "nav" ? Theme.color.accentPurple : "transparent"
                        }

                        Row {
                            anchors {
                                left: parent.left
                                leftMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 8

                            Text {
                                text: navRow.isActive ? navRow.modelData.glyphFilled : navRow.modelData.glyphOutline
                                renderType: Text.NativeRendering
                                color: navRow.isActive ? Theme.color.accentPurple : Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                            }
                            Text {
                                text: navRow.modelData.label
                                color: navRow.isActive ? Theme.color.accentPurple : Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }

                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                SystemState.activeSection = navRow.modelData.id;
                                root.focusZone = "content";
                            }
                        }
                    }
                }
            }

            Item {
                width: inner.width - nav.width - inner.spacing
                height: Math.max(contentLoader.implicitHeight, 100)

                Loader {
                    id: contentLoader
                    width: parent.width
                    active: true
                    sourceComponent: {
                        switch (SystemState.activeSection) {
                        case "about":
                            return aboutComp;
                        case "install":
                            return installComp;
                        case "themes":
                            return themesComp;
                        case "keybinds":
                            return keybindsComp;
                        case "monitor":
                            return monitorComp;
                        case "display":
                            return displayComp;
                        case "services":
                            return servicesComp;
                        case "maintenance":
                            return maintenanceComp;
                        case "power":
                            return powerComp;
                        case "jobs":
                            return jobsComp;
                        default:
                            return null;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: aboutComp
        SystemAbout {}
    }
    Component {
        id: installComp
        SystemInstall {
            searchQuery: root.searchQuery
        }
    }
    Component {
        id: themesComp
        SystemThemes {}
    }
    Component {
        id: keybindsComp
        SystemKeybinds {
            searchQuery: root.searchQuery
        }
    }
    Component {
        id: monitorComp
        SystemMonitor {
            active: SystemState.activeSection === "monitor"
        }
    }
    Component {
        id: displayComp
        SystemDisplay {}
    }
    Component {
        id: servicesComp
        SystemServices {}
    }
    Component {
        id: maintenanceComp
        SystemMaintenance {}
    }
    Component {
        id: powerComp
        SystemPower {}
    }
    Component {
        id: jobsComp
        SystemJobs {}
    }
}
