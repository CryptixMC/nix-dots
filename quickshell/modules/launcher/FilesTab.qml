import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../theme"

// Left: navigable subfolder list + breadcrumb (v1 — a single pane you
// descend/ascend through, not a full expand/collapse multi-level tree;
// this tab was explicitly flagged for further design discussion before
// building the real thing). Right: grid of the current directory's full
// contents. Search (shared searchInput, threaded in via searchQuery)
// filters both in place via FolderListModel.nameFilters, and separately
// surfaces matches *outside* the current directory as a flat path list via
// one bounded `find -iname` call — substring matching, not true fuzzy
// scoring, an honest v1 given the "we'll discuss making this much better"
// framing already set for this tab.
Item {
    id: root
    width: parent.width
    height: Math.min(mainRow.implicitHeight, Theme.spacing.launcherTabBodyMaxHeight)

    property string searchQuery: ""
    readonly property string homeDir: Quickshell.env("HOME")
    property string currentDir: root.homeDir
    readonly property var globFilters: root.searchQuery.trim().length > 0 ? [`*${root.searchQuery.trim()}*`] : ["*"]

    function navigateUp() {
        const parts = root.currentDir.split("/").filter(p => p.length > 0);
        parts.pop();
        root.currentDir = "/" + parts.join("/");
    }

    function openEntry(path, isDir) {
        if (isDir) {
            root.currentDir = path;
        } else {
            Quickshell.execDetached(["xdg-open", path]);
            LauncherState.hide();
        }
    }

    property var outsideMatches: []

    Process {
        id: outsideSearch
        command: ["find", root.homeDir, "-mindepth", "1", "-maxdepth", "6", "-iname", `*${root.searchQuery.trim()}*`, "-not", "-path", `${root.currentDir}/*`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.outsideMatches = text.split("\n").filter(l => l.length > 0).slice(0, 50);
            }
        }
    }

    onSearchQueryChanged: {
        if (root.searchQuery.trim().length === 0) {
            root.outsideMatches = [];
            return;
        }
        outsideSearch.running = false;
        outsideSearch.running = true;
    }

    FolderListModel {
        id: treeModel
        folder: `file://${root.currentDir}`
        showDirsFirst: true
        showDotAndDotDot: false
        showFiles: false
        nameFilters: root.globFilters
    }

    FolderListModel {
        id: gridModel
        folder: `file://${root.currentDir}`
        showDirsFirst: true
        showDotAndDotDot: false
        showFiles: true
        nameFilters: root.globFilters
    }

    Row {
        id: mainRow
        width: parent.width
        spacing: Theme.spacing.gameSectionGap

        Column {
            id: treeColumn
            width: Theme.spacing.fileTreeWidth
            spacing: Theme.spacing.fileGridGap

            Row {
                width: parent.width
                height: Theme.spacing.fileBreadcrumbHeight
                spacing: 6

                Text {
                    id: upArrow
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.currentDir !== "/"
                    text: "←"
                    color: upMouse.containsMouse ? Theme.color.accentPurple : Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    MouseArea {
                        id: upMouse
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.navigateUp()
                    }
                }

                Text {
                    width: parent.width - upArrow.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.currentDir
                    elide: Text.ElideMiddle
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }
            }

            ListView {
                width: parent.width
                height: Theme.spacing.launcherTabBodyMaxHeight - Theme.spacing.fileBreadcrumbHeight - Theme.spacing.fileOutsideListMaxHeight - Theme.spacing.gameSectionGap * 2
                clip: true
                model: treeModel

                delegate: Rectangle {
                    id: treeRow
                    required property string fileName
                    required property string filePath

                    width: ListView.view.width
                    height: Theme.spacing.fileTreeRowHeight
                    color: treeRowMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                    radius: Theme.radius.input

                    Behavior on color {
                        ColorAnimation { duration: Theme.motion.hoverColor.duration }
                    }

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Text {
                            text: "󰉋"
                            renderType: Text.NativeRendering
                            color: Theme.color.accentPurple
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        Text {
                            width: treeColumn.width - 30
                            text: treeRow.fileName
                            elide: Text.ElideRight
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                    }

                    MouseArea {
                        id: treeRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openEntry(treeRow.filePath, true)
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4
                visible: root.outsideMatches.length > 0

                Text {
                    text: "Elsewhere"
                    color: Theme.color.launcherPlaceholderFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }

                ListView {
                    width: parent.width
                    height: Theme.spacing.fileOutsideListMaxHeight
                    clip: true
                    model: root.outsideMatches

                    delegate: Text {
                        id: outsideRow
                        required property string modelData

                        width: ListView.view.width
                        text: outsideRow.modelData
                        elide: Text.ElideMiddle
                        color: outsideMouse.containsMouse ? Theme.color.accentPurple : Theme.color.tooltipFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall

                        MouseArea {
                            id: outsideMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openEntry(outsideRow.modelData, false)
                        }
                    }
                }
            }
        }

        GridView {
            id: grid
            width: mainRow.width - treeColumn.width - mainRow.spacing
            height: Theme.spacing.launcherTabBodyMaxHeight
            clip: true
            cellWidth: Theme.spacing.fileGridCellSize + Theme.spacing.fileGridGap
            cellHeight: Theme.spacing.fileGridCellSize + 20
            model: gridModel

            delegate: Item {
                id: cell
                required property string fileName
                required property string filePath
                required property bool fileIsDir

                width: GridView.view.cellWidth - Theme.spacing.fileGridGap
                height: GridView.view.cellHeight

                Rectangle {
                    id: iconBg
                    width: Theme.spacing.fileGridCellSize
                    height: Theme.spacing.fileGridCellSize - 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: Theme.radius.input
                    color: cellMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.motion.hoverColor.duration }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 32
                        source: Quickshell.iconPath(cell.fileIsDir ? "folder" : "text-x-generic", "application-x-executable")
                    }
                }

                Text {
                    anchors {
                        top: iconBg.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 2
                    }
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: cell.fileName
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openEntry(cell.filePath, cell.fileIsDir)
                }
            }
        }
    }
}
