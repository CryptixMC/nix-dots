import QtQuick
import Quickshell
import "../../theme"

// Bar layout: layer "top", position "top", height 26,
// fixed-center clock, modules-left/center/right layout.
PanelWindow {
    id: bar

    // Variants (in shell.qml) injects each Quickshell.screens entry here —
    // the delegate root must declare this property itself for the model
    // value to land on it.
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
    // `layer` left at PanelWindow's default (top); override explicitly
    // if the default doesn't hold.

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
            // The rightmost module is always tray, so this inset is
            // effectively the bar's right-edge padding.
            rightMargin: Theme.spacing.barRightInset
            verticalCenter: parent.verticalCenter
        }
    }
}
