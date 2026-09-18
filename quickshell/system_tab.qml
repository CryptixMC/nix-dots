import QtQuick 2.15

Rectangle {
    width: parent.width
    height: parent.height
    border: 1
    property real bevelSize: 2

    Column {
        id: systemContent
        spacing: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10

        // System Options section (left column)
        Column {
            width: parent.width * 0.4
            spacing: 8
            
            Text {
                text: "System Options"
                font.bold: true
                font.pixelSize: 16
            }
            
            Button {
                text: "Update NH OS"
                onClicked: {
                    // Implement update functionality here
                    console.log("Updating NH OS...")
                }
            }
            
            Button {
                text: "Update NH Home"
                onClicked: {
                    // Implement update functionality here
                    console.log("Updating NH Home...")
                }
            }
            
            Button {
                text: "Run Flakes Update"
                onClicked: {
                    // Implement flake update functionality here
                    console.log("Updating flakes...")
                }
            }
        }

        // Themes section (right column)
        Column {
            width: parent.width * 0.5
            spacing: 8
            
            Text {
                text: "Theme Previews"
                font.bold: true
                font.pixelSize: 16
            }
            
            Row {
                spacing: 10
                
                // Theme preview items - using current placeholder images
                Rectangle {
                    width: 120; height: 80
                    color: "#333"
                    border.color: "white"
                    border.width: 2
                    
                    Text {
                        text: "Default Dark Theme"
                        anchors.centerIn: parent
                        color: "white"
                        font.pixelSize: 10
                    }
                }
                
                Rectangle {
                    width: 120; height: 80
                    color: "#fff"
                    border.color: "black"
                    border.width: 2
                    
                    Text {
                        text: "Default Light Theme"
                        anchors.centerIn: parent
                        color: "black"
                        font.pixelSize: 10
                    }
                }
            }
            
            Text {
                text: "Currently selected theme: Default Dark (Sharp UI)"
                font.pixelSize: 12
                color: "#ccc"
            }
        }

        // Additional utilities
        Column {
            spacing: 8
            
            Text {
                text: "Utilities" 
                font.bold: true
                font.pixelSize: 16
            }
            
            Row {
                spacing: 10
                
                Button {
                    text: "Open Settings"
                    onClicked: {
                        console.log("Opening settings...")
                    }
                }
                
                Button {
                    text: "Restart Quickshell"
                    onClicked: {
                        console.log("Restarting Quickshell...")
                    }
                }
            }
        }
    }
}