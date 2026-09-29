import QtQuick
import Quickshell.Networking
import "../../theme"

// Pre-login Wi-Fi picker, an in-window panel since cage has no layer shell.
// Wi-Fi devices are detected by having `.networks`; Quickshell.Networking
// has no device-type discrimination API.
Rectangle {
    id: root

    property bool panelVisible: false
    visible: panelVisible
    width: 300
    radius: 3
    color: Colors.panelBg
    border.width: 1
    border.color: Colors.panelBorder

    readonly property var wifiDevices: Networking.devices.values.filter(d => d.networks !== undefined)
    // Deduped by SSID across devices (multiple APs can share one).
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

    // Tracked by name, not object, so it survives list refreshes during a scan.
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
                    radius: 3
                    color: row.modelData.connected ? Colors.bandSelected : "transparent"

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
                            color: Colors.textBody
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
                    radius: 3
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
