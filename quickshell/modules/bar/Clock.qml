import QtQuick
import "../../theme"

// Mirrors waybar's clock format "{:%I:%M %p · %a %d}" (e.g. "02:47 PM · Tue 09").
// Calendar hover-tooltip is deferred — plain formatted time only for this pass.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: 26

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeSmall
        color: Colors.clockFg
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: label.text = Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
    }
}
