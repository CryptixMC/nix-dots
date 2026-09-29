import QtQuick

// Catppuccin's Clock override for Themed.qml, self-contained with literal Mocha colors.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: 26

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(new Date(), "HH:mm:ss · ddd dd MMM")
        font.family: "JetBrainsMono Nerd Font Mono"
        font.pixelSize: 11
        font.bold: true
        color: "#cba6f7"
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: label.text = Qt.formatDateTime(new Date(), "HH:mm:ss · ddd dd MMM")
    }
}
