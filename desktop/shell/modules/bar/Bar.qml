import QtQuick
import Quickshell
import "../../theme"

// Top bar: left workspaces/title, fixed-center clock, right modules.
PanelWindow {
    id: bar

    // Variants injects each screen here; the delegate root must declare
    // this property for the model value to land on it.
    property var modelData
    property var notifServer: null
    property int notifActiveCount: 0

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: Theme.spacing.barHeight
    exclusiveZone: Theme.spacing.barHeight
    color: Theme.color.barBg

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: Theme.spacing.borderHairline
        color: Theme.color.barBorder
    }

    Row {
        spacing: Theme.spacing.flush
        anchors {
            left: parent.left
            leftMargin: Theme.spacing.barLeftInset
            verticalCenter: parent.verticalCenter
        }

        Workspaces {}
        ActiveWindow {}
    }

    Themed {
        componentName: "Clock"
        defaultSource: Qt.resolvedUrl("Clock.qml")
        anchors.centerIn: parent
    }

    RightModules {
        notifServer: bar.notifServer
        notifActiveCount: bar.notifActiveCount
        anchors {
            right: parent.right
            // Tray is always rightmost, so this is the bar's right padding.
            rightMargin: Theme.spacing.barRightInset
            verticalCenter: parent.verticalCenter
        }
    }
}
