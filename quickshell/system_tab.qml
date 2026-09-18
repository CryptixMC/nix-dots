import QtQuick 2.15

Rectangle {
    width: parent.width
    height: parent.height
    border: 1
    property real bevelSize: 2

    // Left section for system options
    Column {
        id: leftSection
        spacing: 10
        Item {
            width: parent.width
            height: 30
            text: "System Options"
        }
        Item {
            width: parent.width
            height: 30
            text: "OS Settings"
        }
    }

    // Right section for additional settings
    Column {
        id: rightSection
        spacing: 10
        Item {
            width: parent.width
            height: 30
            text: "Update NH OS"
        }
        Item {
            width: parent.width
            height: 30
            text: "Update NH Home"
        }
        Item {
            width: parent.width
            height: 30
            text: "Update Flakes"
        }
    }
}
