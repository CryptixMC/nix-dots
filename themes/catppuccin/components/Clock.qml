import QtQuick

// Catppuccin's own custom Clock — proves Themed.qml's component-override
// mechanism end-to-end (real QML replacing the built-in component, not
// just data). Deliberately self-contained with literal Mocha colors rather
// than importing back into quickshell/theme/ — a theme-provided override
// living outside the quickshell/ tree owns its own bespoke styling.
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
