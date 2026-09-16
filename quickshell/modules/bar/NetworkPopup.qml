import QtQuick
import Quickshell
import Quickshell.Networking
import "../../theme"

// Click-to-open network switcher flyout (replaces launching `nmtui`
// directly on click, same pattern as VolumePopup.qml's replacement of a
// direct pavucontrol launch). Known networks connect with one click;
// unknown-but-open networks connect directly too; unknown-and-secured
// networks expand an inline password field (`connectWithPsk`). The "›"
// chevron is the escape hatch for anything this doesn't cover (hidden
// SSIDs, enterprise auth, etc.) — same role as Volume's pavucontrol link.
PopupWindow {
    id: root

    property var anchorItem: null
    property var wifiDevice: null
    property string expandedNetworkName: ""
    property string pendingPassword: ""
    property string errorText: ""

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    readonly property var networks: {
        const list = wifiDevice ? wifiDevice.networks.values.slice() : [];
        list.sort((a, b) => b.signalStrength - a.signalStrength);
        return list;
    }

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: Theme.spacing.launcherWidth
    implicitHeight: content.implicitHeight + Theme.spacing.launcherContentInset * 2

    // Actively scan while open so the list reflects what's really
    // reachable right now, not just whatever NetworkManager last cached —
    // off again on close to avoid burning radio/CPU in the background.
    onVisibleChanged: {
        if (wifiDevice)
            wifiDevice.scannerEnabled = visible;
        if (visible) {
            closeTimer.stop();
            expandedNetworkName = "";
            errorText = "";
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 800
        onTriggered: if (!hover.hovered)
            root.visible = false
    }

    function glyphFor(net) {
        if (net.signalStrength >= 75)
            return "󰤨";
        if (net.signalStrength >= 50)
            return "󰤥";
        if (net.signalStrength >= 25)
            return "󰤢";
        return "󰤟";
    }

    function isSecured(net) {
        return net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Owe;
    }

    function activate(net) {
        errorText = "";
        if (net.connected)
            return;
        if (net.known || !isSecured(net)) {
            net.connect();
            return;
        }
        expandedNetworkName = expandedNetworkName === net.name ? "" : net.name;
        pendingPassword = "";
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.launcherContentInset
            }
            spacing: Theme.spacing.launcherContentGap / 2

            Row {
                width: parent.width
                spacing: Theme.spacing.volumePopupGap

                Text {
                    text: "NETWORKS"
                    color: Theme.color.tooltipMuted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }

                Text {
                    visible: root.errorText.length > 0
                    text: root.errorText
                    color: Theme.color.moduleDisabledFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeSmall
                }
            }

            Repeater {
                model: root.networks

                delegate: Column {
                    id: row
                    required property var modelData
                    width: content.width

                    Connections {
                        target: row.modelData
                        function onConnectionFailed(reason) {
                            root.errorText = "failed to connect to " + row.modelData.name;
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Theme.spacing.launcherRowHeight
                        radius: Theme.radius.input
                        color: row.modelData.connected ? Theme.color.launcherItemSelectedBg : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacing.launcherRowInset
                                rightMargin: Theme.spacing.launcherRowInset
                            }
                            spacing: Theme.spacing.volumePopupGap

                            Text {
                                text: root.glyphFor(row.modelData)
                                color: row.modelData.connected ? Theme.color.accentPurple : Theme.color.rightModuleFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                                renderType: Text.NativeRendering
                            }

                            Text {
                                width: parent.width - 60
                                text: row.modelData.name
                                elide: Text.ElideRight
                                color: Theme.color.fg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeBase
                            }

                            Text {
                                visible: root.isSecured(row.modelData)
                                text: "󰌾"
                                color: Theme.color.tooltipMuted
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activate(row.modelData)
                        }
                    }

                    // Inline password entry for an unknown secured network
                    // — expands under its row instead of a separate dialog,
                    // collapses again on connect/Escape/re-click.
                    Rectangle {
                        visible: root.expandedNetworkName === row.modelData.name
                        width: parent.width
                        height: visible ? Theme.spacing.launcherInputHeight : 0
                        radius: Theme.radius.input
                        color: Theme.color.launcherInputBg
                        border.width: Theme.spacing.borderHairline
                        border.color: Theme.color.launcherInputBorder
                        clip: true

                        TextInput {
                            anchors {
                                fill: parent
                                margins: Theme.spacing.launcherInputTextInset
                            }
                            echoMode: TextInput.Password
                            color: Theme.color.fg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                            focus: root.expandedNetworkName === row.modelData.name

                            Keys.onEscapePressed: root.expandedNetworkName = ""
                            onAccepted: {
                                row.modelData.connectWithPsk(text);
                                root.expandedNetworkName = "";
                            }
                        }
                    }
                }
            }

            Text {
                text: "› more options (nmtui)"
                color: Theme.color.rightModuleFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["ghostty", "-e", "nmtui"]);
                        root.visible = false;
                    }
                }
            }
        }
    }
}
