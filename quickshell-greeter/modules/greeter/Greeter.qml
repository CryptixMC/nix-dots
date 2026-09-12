import QtQuick
import Quickshell
import "../../theme"
import "../auth"
import "../network"
import "../status"

// Root visible surface, one per screen (see shell.qml's Variants). cage
// does not implement wlr-layer-shell (confirmed from its own source/docs —
// plain xdg_shell kiosk compositor), so this is a FloatingWindow, not the
// PanelWindow the rest of this repo's Quickshell surfaces use — cage
// forces it fullscreen/kiosk on its own.
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

        // Clock, top-right — trimmed inline copy of
        // quickshell/modules/bar/Clock.qml's logic rather than an import,
        // same decoupling rationale as theme/Colors.qml.
        Text {
            id: clock
            anchors {
                top: parent.top
                right: parent.right
                topMargin: 24
                rightMargin: 24
            }
            text: Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
            color: Colors.mutedFg
            font.family: Colors.fontFamily
            font.pixelSize: Colors.fontSizeBase

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatDateTime(new Date(), "hh:mm AP · ddd dd")
            }
        }

        // Network icon + panel, top-left — GDM's own login-screen network
        // affordance is in this same corner.
        Text {
            id: networkIcon
            anchors {
                top: parent.top
                left: parent.left
                topMargin: 24
                leftMargin: 24
            }
            text: "󰖩"
            color: Colors.mutedFg
            font.family: Colors.fontFamily
            font.pixelSize: Colors.fontSizeLarge
            renderType: Text.NativeRendering

            MouseArea {
                anchors.fill: parent
                onClicked: networkPanel.panelVisible = !networkPanel.panelVisible
            }
        }

        NetworkPanel {
            id: networkPanel
            anchors {
                top: networkIcon.bottom
                left: parent.left
                topMargin: 8
                leftMargin: 24
            }
        }

        // Status row, top-right below the clock — read-only at the login
        // screen (nothing here needs to be interactive pre-login besides
        // Wi-Fi, which already has its own picker above).
        Row {
            anchors {
                top: clock.bottom
                right: parent.right
                topMargin: 8
                rightMargin: 24
            }
            spacing: 16

            Battery {}
            Brightness {}
            Volume {}
            BluetoothStatus {}
        }
    }
}
