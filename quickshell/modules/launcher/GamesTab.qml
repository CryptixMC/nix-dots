import QtQuick
import Quickshell
import "../../theme"

// Recommended row (most-recently-played — the only honest "recommended"
// signal available without a real usage-scoring system) + full library
// grid + one grid per launcher. Search (shared searchInput, threaded in via
// searchQuery) filters entries by name within each section rather than
// collapsing the section layout.
Item {
    id: root
    width: parent.width
    // implicitHeight mirrors height explicitly — a plain Item doesn't
    // auto-derive implicitHeight from children the way Column/Row do, so
    // leaving it unset here would report 0 to anything (e.g. a Loader)
    // that reads implicitHeight rather than the real, bounded height.
    height: Math.min(inner.implicitHeight, Theme.spacing.launcherTabBodyMaxHeight)
    implicitHeight: root.height

    property string searchQuery: ""

    function matchesSearch(entry) {
        const q = root.searchQuery.trim().toLowerCase();
        return q.length === 0 || entry.name.toLowerCase().includes(q);
    }

    readonly property var recommended: GamesLibrary.entries.slice().sort((a, b) => b.lastPlayed - a.lastPlayed).slice(0, 10)
    readonly property var filteredAll: GamesLibrary.entries.filter(root.matchesSearch)
    readonly property var launchers: [...new Set(GamesLibrary.entries.map(e => e.launcher))]

    Component {
        id: cardDelegate

        Rectangle {
            id: card
            required property var modelData
            width: Theme.spacing.gameCardWidth
            height: Theme.spacing.gameCardImageHeight + 28
            color: "transparent"

            Rectangle {
                id: art
                width: parent.width
                height: Theme.spacing.gameCardImageHeight
                radius: Theme.radius.input
                // Slightly transparent base — only visible for the no-cover-
                // art fallback below, since real box art fills the rect
                // completely; kept subtle rather than solid either way.
                color: ThemeDefaults.alpha(Theme.base16.base02, 0.5)
                border.width: mouse.containsMouse ? 2 : 0
                border.color: Theme.color.accentPurple
                clip: true

                Behavior on border.width {
                    NumberAnimation { duration: Theme.motion.hoverColor.duration }
                }

                Image {
                    anchors.fill: parent
                    visible: card.modelData.iconSource.length > 0
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: card.modelData.iconSource
                }

                Text {
                    anchors.centerIn: parent
                    visible: card.modelData.iconSource.length === 0
                    text: "󰺵"
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: 32
                    color: Theme.color.accentPurple
                }
            }

            Text {
                anchors {
                    top: art.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 4
                }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.modelData.name
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    card.modelData.launch();
                    LauncherState.hide();
                }
            }
        }
    }

    component SectionLabel: Text {
        color: Theme.color.launcherPlaceholderFg
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
        font.bold: true
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: inner.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: inner
            width: parent.width
            spacing: Theme.spacing.gameSectionGap

            Column {
                width: parent.width
                spacing: Theme.spacing.gameSectionHeaderGap
                visible: root.recommended.length > 0

                SectionLabel {
                    text: "Recommended"
                }

                ListView {
                    width: parent.width
                    height: Theme.spacing.gameRecommendedRowHeight
                    orientation: ListView.Horizontal
                    spacing: Theme.spacing.gameCardGap
                    model: root.recommended
                    delegate: cardDelegate
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacing.gameSectionHeaderGap
                visible: root.filteredAll.length > 0

                SectionLabel {
                    text: "Library"
                }

                GridView {
                    width: parent.width
                    height: Math.min(contentHeight, Theme.spacing.gameGridRowHeight * 2)
                    clip: true
                    interactive: false
                    cellWidth: Theme.spacing.gameCardWidth + Theme.spacing.gameCardGap
                    cellHeight: Theme.spacing.gameGridRowHeight
                    model: root.filteredAll
                    delegate: cardDelegate
                }
            }

            Repeater {
                model: root.launchers

                delegate: Column {
                    id: section
                    required property string modelData
                    width: inner.width
                    spacing: Theme.spacing.gameSectionHeaderGap

                    readonly property var sectionEntries: root.filteredAll.filter(e => e.launcher === section.modelData)
                    visible: sectionEntries.length > 0

                    SectionLabel {
                        text: section.modelData
                    }

                    GridView {
                        width: section.width
                        height: Math.min(contentHeight, Theme.spacing.gameGridRowHeight * 2)
                        clip: true
                        interactive: false
                        cellWidth: Theme.spacing.gameCardWidth + Theme.spacing.gameCardGap
                        cellHeight: Theme.spacing.gameGridRowHeight
                        model: section.sectionEntries
                        delegate: cardDelegate
                    }
                }
            }

            Text {
                visible: GamesLibrary.entries.length === 0
                text: "No games found (Steam/Prism Launcher libraries empty or not installed)."
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
            }
        }
    }
}
