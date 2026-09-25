import QtQuick
import "../../theme"

// Every command JobRunner has run this session, most recent first (JobRunner
// itself prepends new jobs, so no sorting needed here). Replaces the
// Ghostty-window-per-command model everywhere else in this tab: output
// streams live into each job's own pane instead of a terminal that closes
// and loses it. Running jobs auto-expand; finished ones start collapsed
// (click the header to toggle) so a long history doesn't turn into a wall
// of old logs.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property var expandedIds: ({})

    function isExpanded(job) {
        return job.state === "running" || root.expandedIds[job.id] === true;
    }

    function toggle(job) {
        const next = Object.assign({}, root.expandedIds);
        next[job.id] = !root.isExpanded(job);
        root.expandedIds = next;
    }

    function stateLabel(state) {
        switch (state) {
        case "running":
            return "running";
        case "ok":
            return "done";
        case "failed":
            return "failed";
        case "cancelled":
            return "cancelled";
        default:
            return state;
        }
    }

    function stateColor(state) {
        switch (state) {
        case "running":
            return Theme.color.accentPurple;
        case "failed":
            return Theme.color.critical;
        default:
            return Theme.color.launcherPlaceholderFg;
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Row {
            width: parent.width
            spacing: 8

            Text {
                text: "Jobs"
                font.bold: true
                font.pixelSize: 16
                color: Theme.color.fg
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: JobRunner.runningCount > 0
                text: `${JobRunner.runningCount} running`
                color: Theme.color.accentPurple
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }

        Text {
            visible: JobRunner.jobs.length === 0
            text: "No commands have run yet this session -- update buttons, service restarts, and maintenance actions all land here instead of opening a terminal."
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Repeater {
            model: JobRunner.jobs

            delegate: Rectangle {
                id: card
                required property var modelData
                width: column.width
                implicitHeight: cardColumn.implicitHeight + Theme.spacing.jobCardPadY * 2
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: card.modelData.state === "running" ? Theme.color.accentPurple : Theme.color.launcherBorder

                Column {
                    id: cardColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: Theme.spacing.jobCardPadX
                    }
                    topPadding: Theme.spacing.jobCardPadY
                    spacing: Theme.spacing.jobHeaderGap

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.stateColor(card.modelData.state)
                        }

                        Text {
                            width: parent.width - 180
                            elide: Text.ElideRight
                            text: card.modelData.label
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                            font.bold: true

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggle(card.modelData)
                            }
                        }

                        Text {
                            text: root.stateLabel(card.modelData.state) + (card.modelData.exitCode !== null && card.modelData.state === "failed" ? ` (${card.modelData.exitCode})` : "")
                            color: root.stateColor(card.modelData.state)
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }

                        Rectangle {
                            width: 70
                            height: 20
                            visible: card.modelData.state === "running"
                            radius: Theme.radius.input
                            color: cancelMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                            border.width: Theme.spacing.borderHairline
                            border.color: Theme.color.launcherBorder

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall - 1
                            }
                            MouseArea {
                                id: cancelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: JobRunner.cancel(card.modelData.id)
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: card.modelData.argv.join(" ")
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall - 1
                    }

                    Rectangle {
                        width: parent.width
                        visible: root.isExpanded(card.modelData) && card.modelData.output.length > 0
                        height: Math.min(Theme.spacing.jobOutputMaxHeight, outputText.implicitHeight + Theme.spacing.jobOutputPad * 2)
                        radius: Theme.radius.input
                        color: ThemeDefaults.alpha(Theme.base16.base00, 0.6)
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.jobOutputPad
                            contentWidth: width
                            contentHeight: outputText.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            // Pin scroll to the bottom while the job is still
                            // running and the view is already at (or near)
                            // the bottom -- a live tail, not a jump-to-top
                            // every time a line arrives.
                            onContentHeightChanged: if (card.modelData.state === "running")
                                contentY = Math.max(0, contentHeight - height)

                            Text {
                                id: outputText
                                width: parent.width
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                text: card.modelData.output.join("\n")
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall - 1
                            }
                        }
                    }
                }
            }
        }
    }
}
