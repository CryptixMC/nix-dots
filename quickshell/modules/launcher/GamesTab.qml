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
    // `height` and `implicitHeight` are both bound to the SAME independent
    // expression rather than one deriving from the other — binding
    // `implicitHeight: root.height` (tried first) created a genuine
    // binding loop and silently froze at the first-computed value instead
    // of reacting to inner.implicitHeight changing later (confirmed live:
    // stuck at ~18px — just the "no games found" fallback text's height —
    // even once 36 real games had loaded and inner.implicitHeight had
    // correctly grown to 1736). Item.height's *implicit* default binding
    // is implicitHeight, so anything that makes implicitHeight depend on
    // height, even indirectly, risks exactly this loop.
    readonly property real computedHeight: Math.min(inner.implicitHeight, Theme.spacing.launcherTabBodyMaxHeight)
    height: root.computedHeight
    implicitHeight: root.computedHeight

    property string searchQuery: ""

    // Keyboard navigation (Launcher.qml's Left/Right arrow handling) only
    // drives the Recommended row -- it's the one real horizontal strip;
    // Library/per-launcher content is a grid, so "left/right" has no
    // single obvious meaning there. moveLeft/moveRight return false at
    // either end so the caller knows to switch tabs instead of no-op'ing
    // silently, matching Liam's own explicit ask: "if there is nothing to
    // move forward or backwards for I should be able to use the arrow
    // keys to switch tabs as well" (real quote, sessions.db transcript).
    property int currentIndex: 0

    function moveLeft() {
        if (root.currentIndex > 0) {
            root.currentIndex--;
            return true;
        }
        return false;
    }

    function moveRight() {
        if (root.currentIndex < root.recommended.length - 1) {
            root.currentIndex++;
            return true;
        }
        return false;
    }

    function launchCurrent() {
        const entry = root.recommended[root.currentIndex];
        if (entry) {
            entry.launch();
            LauncherState.hide();
        }
    }

    // GamesLibrary.entries can populate asynchronously after this tab is
    // already active (real Steam/Prism scans, not instant) -- without this,
    // an in-flight currentIndex from a longer previous list could point
    // past the end of a freshly-shrunk one.
    onRecommendedChanged: {
        if (root.currentIndex >= root.recommended.length)
            root.currentIndex = Math.max(0, root.recommended.length - 1);
    }

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

    // Recommended row only -- the one section this is a genuinely
    // meaningful "current selection" for (a single horizontal strip;
    // Library/per-launcher below are grids with no single obvious
    // left/right order). Otherwise identical to cardDelegate, just with
    // an extra border driven by keyboard state (root.currentIndex) on top
    // of the existing hover-driven one, so mouse and keyboard highlighting
    // never fight over the same border.width binding.
    Component {
        id: recommendedCardDelegate

        Rectangle {
            id: rcard
            required property var modelData
            required property int index
            readonly property bool current: index === root.currentIndex
            width: Theme.spacing.gameCardWidth
            height: Theme.spacing.gameCardImageHeight + 28
            color: "transparent"

            Rectangle {
                id: rart
                width: parent.width
                height: Theme.spacing.gameCardImageHeight
                radius: Theme.radius.input
                color: ThemeDefaults.alpha(Theme.base16.base02, 0.5)
                border.width: (rmouse.containsMouse || rcard.current) ? 2 : 0
                border.color: Theme.color.accentPurple
                clip: true

                Behavior on border.width {
                    NumberAnimation { duration: Theme.motion.hoverColor.duration }
                }

                Image {
                    anchors.fill: parent
                    visible: rcard.modelData.iconSource.length > 0
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: rcard.modelData.iconSource
                }

                Text {
                    anchors.centerIn: parent
                    visible: rcard.modelData.iconSource.length === 0
                    text: "󰺵"
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: 32
                    color: Theme.color.accentPurple
                }
            }

            Text {
                anchors {
                    top: rart.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: 4
                }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: rcard.modelData.name
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            MouseArea {
                id: rmouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.currentIndex = rcard.index
                onClicked: {
                    rcard.modelData.launch();
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
                    id: recommendedList
                    width: parent.width
                    height: Theme.spacing.gameRecommendedRowHeight
                    orientation: ListView.Horizontal
                    spacing: Theme.spacing.gameCardGap
                    clip: true
                    model: root.recommended
                    delegate: recommendedCardDelegate
                    // Keeps the keyboard-highlighted card scrolled into
                    // view as currentIndex changes via Launcher.qml's
                    // arrow-key handling -- ListView's own currentIndex
                    // (not just root.currentIndex) drives this, so they're
                    // kept in sync here rather than duplicating
                    // positionViewAtIndex calls at every root.currentIndex
                    // change site.
                    currentIndex: root.currentIndex
                    highlightMoveDuration: Theme.motion.hoverColor.duration
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
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
