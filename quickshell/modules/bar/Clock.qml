import QtQuick
import "../../theme"

// Clock, formatted as "hh:mm AP · ddd dd" (e.g. "02:47 PM · Tue 09").
// Click opens a month-grid calendar (CalendarPopup.qml) -- deferred since
// the very first pass, built now on the same VolumePopup-derived template
// every other bar flyout uses.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: Theme.spacing.barHeight

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
        color: hoverArea.containsMouse ? Theme.color.purpleHover : Theme.color.clockFg

        Behavior on color {
            ColorAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: label.text = Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
    }

    CalendarPopup {
        id: popup
        anchorItem: root
    }
}
