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

        // System status cluster, top-left — every pre-login setting/status
        // (network, battery, brightness, volume, bluetooth) together in one
        // place, alongside the Wi-Fi icon, rather than split across two
        // corners the way Wi-Fi (top-left) and everything else (top-right,
        // under the clock) used to be. GDM's own login-screen network
        // affordance is in this same top-left corner; the rest joins it
        // here. Wi-Fi is the only one with a click target/panel — the
        // others stay read-only at the login screen, nothing else here
        // needs to be interactive pre-login.
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
                // textBody, matching the real bar's Network.qml -- no
                // glyphColorOverride there at all, so it's always plain
                // grey regardless of connection state, not an accent
                // colour.
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
