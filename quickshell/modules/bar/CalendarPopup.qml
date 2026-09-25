import QtQuick
import Quickshell
import "../../theme"

// Month grid on click, same structural template as VolumePopup.qml
// (PopupWindow, anchor.item/edges/gravity/adjustment, HoverHandler-driven
// auto-close, grabFocus: false). Clock.qml's own header comment flagged
// this as deferred since the very first pass -- no new popup architecture
// invented to build it now.
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
        // Always reopen on today's month rather than wherever a previous
        // session left the nav -- a calendar that silently remembers last
        // month is a worse default than one that resets. `today` is
        // refreshed here too, not just on creation -- a `date`-typed
        // property initializer only evaluates once, so a shell that's
        // been running for days would otherwise keep highlighting the
        // day it was launched on forever.
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

    // Cells for a 6x7 grid: leading days from the previous month, every day
    // of the viewed month, trailing days from the next month -- always
    // exactly 42 cells so the grid height never changes between months.
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
