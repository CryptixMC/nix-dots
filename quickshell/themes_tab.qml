import QtQuick 2.15

Rectangle {
    width: parent.width
    height: parent.height
    border: 1
    property real bevelSize: 5

    GridLayout {
        columns: 3
        spacing: 10
        anchors.centerIn: parent

        // Placeholder for theme images
        Item {
            width: 100
            height: 100
            Image {
                source: "themes/catppuccin/wallpapers/catppuccin.jpg"
                width: 100
                height: 100
            }
        }
        Item {
            width: 100
            height: 100
            Image {
                source: "themes/ultraviolet/wallpapers/ultraviolet.jpg"
                width: 100
                height: 100
            }
        }
        Item {
            width: 100
            height: 100
            // Add more themes here
        }
    }
}
