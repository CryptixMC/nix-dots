import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"

// Themed polkit prompt. Fingerprint needs no separate path: pam.d/polkit-1 runs
// pam_fprintd alongside pam_unix on the same conversation.
// `visible` binds to `isActive` and UI state is a snapshot refreshed from the
// flow's *Changed signals; binding directly to `flow` properties never updates.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: PolkitAgentService.isActive
    focusable: true

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    property string currentMessage: ""
    property string currentSupplementary: ""
    property bool supplementaryIsError: false
    property bool responseRequired: false
    property bool responseVisible: false

    function syncFromFlow() {
        const flow = PolkitAgentService.flow;
        if (!flow)
            return;
        root.currentMessage = flow.message ?? "";
        root.currentSupplementary = flow.supplementaryMessage ?? "";
        root.supplementaryIsError = !!flow.supplementaryIsError;
        root.responseRequired = !!flow.isResponseRequired;
        root.responseVisible = !!flow.responseVisible;
    }

    function beginFlow() {
        field.text = "";
        root.syncFromFlow();
        // Without a selectedIdentity every submit fails "Not authorized".
        // identities[0] assumes a single admin user.
        const flow = PolkitAgentService.flow;
        if (flow && flow.identities && flow.identities.length > 0)
            flow.selectedIdentity = flow.identities[0];
        Qt.callLater(() => field.forceActiveFocus());
    }

    Connections {
        target: PolkitAgentService
        function onAuthenticationRequestStarted() {
            root.beginFlow();
        }
    }

    // `target` is a binding, so this follows each new flow.
    Connections {
        target: PolkitAgentService.flow

        function onIsResponseRequiredChanged() {
            root.syncFromFlow();
            if (!root.responseRequired)
                field.text = "";
        }
        function onInputPromptChanged() {
            root.syncFromFlow();
        }
        function onResponseVisibleChanged() {
            root.syncFromFlow();
        }
        function onSupplementaryMessageChanged() {
            root.syncFromFlow();
        }
        function onSupplementaryIsErrorChanged() {
            root.syncFromFlow();
        }
        // isResponseRequired stays true on retry, so clear the field here.
        function onAuthenticationFailed() {
            root.syncFromFlow();
            field.text = "";
            Qt.callLater(() => field.forceActiveFocus());
        }
    }

    function submit() {
        if (PolkitAgentService.flow && root.responseRequired)
            PolkitAgentService.flow.submit(field.text);
    }

    function cancel() {
        if (PolkitAgentService.flow)
            PolkitAgentService.flow.cancelAuthenticationRequest();
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.cancel()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancel()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Theme.spacing.authPromptWidth
        height: card.implicitHeight + Theme.spacing.authPromptPadY * 2
        radius: Theme.radius.popup
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.accentPurple

        MouseArea {
            anchors.fill: parent
            // Keeps clicks from reaching the cancel backdrop.
        }

        Column {
            id: card
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.authPromptPadX
            }
            topPadding: Theme.spacing.authPromptPadY
            spacing: Theme.spacing.authPromptGap

            Text {
                // \u{} escape: raw glyph bytes in this range get corrupted to "".
                text: "\u{F033E}" // md-lock
                renderType: Text.NativeRendering
                font.family: Theme.font.family
                font.pixelSize: Theme.spacing.authPromptIconSize
                color: Theme.color.accentPurple
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.currentMessage
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                font.bold: true
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                visible: text.length > 0
                text: root.currentSupplementary
                color: root.supplementaryIsError ? Theme.color.critical : Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "fingerprint also accepted"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Rectangle {
                width: parent.width
                height: Theme.spacing.authPromptInputHeight
                visible: root.responseRequired
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                TextInput {
                    id: field
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase

                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: root.cancel()
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacing.authPromptGap
                bottomPadding: Theme.spacing.authPromptPadY

                Rectangle {
                    width: 90
                    height: 28
                    radius: Theme.radius.input
                    color: cancelMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.launcherBorder

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancel()
                    }
                }

                Rectangle {
                    width: 90
                    height: 28
                    visible: root.responseRequired
                    radius: Theme.radius.input
                    color: submitMouse.containsMouse ? Theme.color.launcherTabActiveBg : Theme.color.accentPurple
                    border.width: Theme.spacing.borderHairline
                    border.color: Theme.color.accentPurple

                    Text {
                        anchors.centerIn: parent
                        text: "Unlock"
                        color: Theme.color.launcherTabActiveFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    MouseArea {
                        id: submitMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submit()
                    }
                }
            }
        }
    }
}
