import QtQuick 2.15
import Quickshell.Widgets
import "../../../theme"

Item {
    width: parent.width
    height: implicitHeight
    
    // System Options section (left column)
    Column {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 8
        
        Text {
            text: "System Options"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }
        
        Button {
            text: "Update NH OS"
            width: 200
            height: Theme.spacing.launcherRowHeight
            // This would normally be connected to an update function
            onClicked: console.log("System tab: Update NH OS clicked")
            
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.input
                color: Theme.color.launcherItemSelectedBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.accentPurple
                
                Text {
                    anchors.centerIn: parent
                    text: "Update NH OS"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }
            }
        }
        
        Button {
            text: "Update NH Home"
            width: 200
            height: Theme.spacing.launcherRowHeight
            onClicked: console.log("System tab: Update NH Home clicked")
            
            Rectangle {
                anchors.fill: parent
                radius: Theme.radius.input
                color: Theme.color.launcherItemSelectedBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.accentPurple
                
                Text {
                    anchors.centerIn: parent
                    text: "Update NH Home"
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }
            }
        }
        
        // Also include a section for system info or config
        Text {
            text: "System Status"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
            anchors { left: parent.left; top: parent.top; margins: 20 }
        }
        
        Rectangle {
            width: 350
            height: 80
            radius: Theme.radius.input
            color: Theme.color.launcherItemSelectedBg
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.accentPurple
            anchors { left: parent.left; top: parent.top; margins: 20 }
            
            Text {
                anchors.centerIn: parent
                text: "OS Version: Ubuntu 22.04\nKernel: 5.15.x\nCPU: Quad-Core\nRAM: 8GB"
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                textFormat: Text.PlainText
            }
        }
    }
}