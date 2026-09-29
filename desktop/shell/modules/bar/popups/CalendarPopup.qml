import QtQuick
import Quickshell
import "../../../theme"

// Click-to-open month grid, on the same popup template as VolumePopup.qml.
PopupWindow {
    id: root

    property var anchorItem: null
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: Theme.spacing.calendarWidth
    implicitHeight: content.implicitHeight + Theme.spacing.calendarPadY * 2

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: if (!hover.hovered)
            root.visible = false
    }
    onVisibleChanged: if (visible) {
        closeTimer.stop();
        // Reset to today's month on every open, and refresh `today`: its
        // initializer only runs once, so a long-running shell would go stale.
        const now = new Date();
        root.today = now;
        root.viewYear = now.getFullYear();
        root.viewMonth = now.getMonth();
    }

    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth() // 0-11

    function prevMonth() {
        if (root.viewMonth === 0) {
            root.viewMonth = 11;
            root.viewYear--;
        } else
            root.viewMonth--;
    }
    function nextMonth() {
        if (root.viewMonth === 11) {
            root.viewMonth = 0;
            root.viewYear++;
        } else
            root.viewMonth++;
    }

    // Always 42 cells (6x7, padded with adjacent months) so the grid
    // height stays constant between months.
    readonly property var cells: {
        const firstOfMonth = new Date(root.viewYear, root.viewMonth, 1);
        const startWeekday = firstOfMonth.getDay(); // 0 = Sunday
        const daysInMonth = new Date(root.viewYear, root.viewMonth + 1, 0).getDate();
        const daysInPrevMonth = new Date(root.viewYear, root.viewMonth, 0).getDate();

        const out = [];
        for (let i = 0; i < startWeekday; i++)
            out.push({ day: daysInPrevMonth - startWeekday + 1 + i, inMonth: false, isToday: false });
        for (let d = 1; d <= daysInMonth; d++)
            out.push({
                day: d,
                inMonth: true,
                isToday: d === root.today.getDate() && root.viewMonth === root.today.getMonth() && root.viewYear === root.today.getFullYear()
            });
        while (out.length < 42)
            out.push({ day: out.length - startWeekday - daysInMonth + 1, inMonth: false, isToday: false });
        return out;
    }

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    Rectangle {
        anchors.fill: parent
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.calendarPadX
            }
            topPadding: Theme.spacing.calendarPadY
            bottomPadding: Theme.spacing.calendarPadY
            spacing: Theme.spacing.calendarHeaderGap

            Row {
                width: parent.width

                Text {
                    text: "\u{F0141}" // md-chevron_left
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    color: Theme.color.rightModuleFg
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.prevMonth() }
                }

                Text {
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    text: `${root.monthNames[root.viewMonth]} ${root.viewYear}`
                    color: Theme.color.tooltipFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                    font.bold: true
                }

                Text {
                    text: "\u{F0142}" // md-chevron_right
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    color: Theme.color.rightModuleFg
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.nextMonth() }
                }
            }

            Grid {
                width: parent.width
                columns: 7
                rowSpacing: Theme.spacing.calendarRowGap
                columnSpacing: 0

                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    delegate: Text {
                        required property string modelData
                        width: Theme.spacing.calendarCellSize
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.color.tooltipMuted
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        font.bold: true
                    }
                }

                Repeater {
                    model: root.cells
                    delegate: Item {
                        required property var modelData
                        width: Theme.spacing.calendarCellSize
                        height: Theme.spacing.calendarCellSize

                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.spacing.calendarCellSize - 4
                            height: Theme.spacing.calendarCellSize - 4
                            radius: Theme.radius.input
                            color: parent.modelData.isToday ? Theme.color.accentPurple : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: parent.parent.modelData.day
                                color: parent.parent.modelData.isToday ? Theme.color.launcherTabActiveFg : (parent.parent.modelData.inMonth ? Theme.color.tooltipFg : Theme.color.tooltipMuted)
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }
                    }
                }
            }
        }
    }
}
