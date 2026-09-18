import QtQuick 2.15
import Quickshell.Widgets
import "../../../theme"

Item {
    width: parent.width
    height: implicitHeight
    
    // This would need to contain the actual system tab content
    Column {
        anchors.centerIn: parent
        spacing: Theme.spacing.launcherContentGap
        
        Text {
            text: "System Options (coming soon)"
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeBase
        }
        
        // Placeholder buttons for the system functionality
        Rectangle {
            width: 200
            height: Theme.spacing.launcherRowHeight
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
        
        Rectangle {
            width: 200
            height: Theme.spacing.launcherRowHeight
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
}