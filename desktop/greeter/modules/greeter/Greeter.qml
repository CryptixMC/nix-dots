import QtQuick
import Quickshell
import "../../theme"
import "../auth"
import "../network"
import "../status"

// One window per screen. cage has no wlr-layer-shell, so this is a
// FloatingWindow (cage makes it fullscreen), not a PanelWindow.
FloatingWindow {
    id: root

    property var modelData

    screen: modelData
    visible: true
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080

    Wallpaper {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.bgOverlay

        Column {
            anchors.centerIn: parent
            spacing: 16
            width: 340

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Config.username
                color: Colors.fg
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeLarge
            }

            PasswordField {
                width: parent.width
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: text.length > 0
                text: AuthState.errorMessage
                color: Colors.errorRed
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeBase
                wrapMode: Text.Wrap
            }
        }

        // Inline clock rather than importing the shell's, to stay decoupled.
        Text {
            id: clock
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 24
                rightMargin: 24
            }
            text: Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
            color: Colors.clockFg
            font.family: Colors.fontFamily
            font.pixelSize: Colors.fontSizeBase

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
            }
        }

        // Status cluster, top-left; only Wi-Fi is interactive pre-login.
        Row {
            id: statusRow
            anchors {
                top: parent.top
                left: parent.left
                topMargin: 24
                leftMargin: 24
            }
            spacing: 16

            Text {
                id: networkIcon
                text: "󰖩"
                color: Colors.textBody
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeLarge
                renderType: Text.NativeRendering

                MouseArea {
                    anchors.fill: parent
                    onClicked: networkPanel.panelVisible = !networkPanel.panelVisible
                }
            }

            Battery {}
            Brightness {}
            Volume {}
            BluetoothStatus {}
        }

        NetworkPanel {
            id: networkPanel
            anchors {
                top: statusRow.bottom
                left: parent.left
                topMargin: 8
                leftMargin: 24
            }
        }
    }
}
