import QtQuick
import Quickshell.Networking
import "../../theme"

// GDM-style pre-login Wi-Fi picker. Plain in-scene panel (Rectangle), not a
// separate PopupWindow — cage has no wlr-layer-shell, and this whole
// greeter is a single FloatingWindow, so a second Quickshell surface would
// be uncharted territory here; toggling visibility within the one window
// is simpler and avoids that risk entirely.
//
// Reuses the same duck-typed wifi-device detection already proven in
// quickshell/modules/bar/Network.qml: Quickshell.Networking has no
// confirmed WifiDevice/WiredDevice type-discrimination API, so devices are
// filtered by the presence of `.networks`, which only a WifiDevice exposes.
Rectangle {
    id: root

    property bool panelVisible: false
    visible: panelVisible
    width: 300
    radius: 8
    color: Colors.panelBg
    border.width: 1
    border.color: Colors.panelBorder

    readonly property var wifiDevices: Networking.devices.values.filter(d => d.networks !== undefined)
    // Flattened across every wifi device (usually just one) and deduped by
    // name — a network can appear more than once if multiple APs share an
    // SSID, which isn't useful to show twice here.
    readonly property var networks: {
        const seen = new Set();
        const all = [];
        for (const dev of wifiDevices) {
            for (const net of dev.networks.values) {
                if (seen.has(net.name))
                    continue;
                seen.add(net.name);
                all.push(net);
            }
        }
        return all.sort((a, b) => b.signalStrength - a.signalStrength);
    }

    // Which network's inline password field is currently open, by name —
    // string rather than holding the Network object directly so it survives
    // the list model refreshing during a scan.
    property string pskPromptFor: ""

    implicitHeight: content.implicitHeight + 20

    Column {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 10
        }
        spacing: 6

        Row {
            width: parent.width
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Wi-Fi"
                color: Colors.fg
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeBase
                font.bold: true
            }

            Item {
                width: parent.width - 60
                height: 1
            }

            Rectangle {
                width: 36
                height: 18
                radius: 9
                anchors.verticalCenter: parent.verticalCenter
                color: Networking.wifiEnabled ? Colors.accentPurple : Colors.inputBg
                border.width: 1
                border.color: Colors.inputBorder

                MouseArea {
                    anchors.fill: parent
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }
        }

        Repeater {
            model: root.networks

            Column {
                id: row
                required property var modelData
                width: content.width
                spacing: 4

                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 4
                    color: row.modelData.connected ? Qt.rgba(176 / 255, 71 / 255, 255 / 255, 0.12) : "transparent"

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 6

                        Text {
                            text: row.modelData.security === WifiSecurityType.Open ? "󰤨" : "󰤪"
                            color: Colors.mutedFg
                            font.family: Colors.fontFamily
                            font.pixelSize: Colors.fontSizeBase
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width - 40
                            text: row.modelData.name
                            color: Colors.fg
                            font.family: Colors.fontFamily
                            font.pixelSize: Colors.fontSizeBase
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (row.modelData.connected)
                                return;
                            if (row.modelData.security === WifiSecurityType.Open)
                                row.modelData.connect();
                            else
                                root.pskPromptFor = root.pskPromptFor === row.modelData.name ? "" : row.modelData.name;
                        }
                    }
                }

                Rectangle {
                    visible: root.pskPromptFor === row.modelData.name
                    width: parent.width
                    height: 32
                    radius: 4
                    color: Colors.inputBg
                    border.width: 1
                    border.color: Colors.inputBorder

                    TextInput {
                        id: pskInput
                        anchors {
                            fill: parent
                            margins: 8
                        }
                        color: Colors.fg
                        font.family: Colors.fontFamily
                        font.pixelSize: Colors.fontSizeBase
                        echoMode: TextInput.Password

                        onAccepted: {
                            if (text.length === 0)
                                return;
                            row.modelData.connectWithPsk(text);
                            text = "";
                            root.pskPromptFor = "";
                        }
                    }
                }
            }
        }
    }
}
