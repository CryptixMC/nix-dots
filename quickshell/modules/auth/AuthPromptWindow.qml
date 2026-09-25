import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../theme"

// Themed replacement for polkit-gnome's authentication dialog. Fingerprint
// needs no separate UI path here: /etc/pam.d/polkit-1 races pam_fprintd
// ahead of pam_unix, so a finger on the reader satisfies the exact same
// conversation this password field is waiting on.
//
// Visibility and updates follow Omarchy's own PolkitAgent.qml (a shipping
// production integration of this exact Quickshell API), not a naive direct
// binding to `PolkitAgentService.flow !== null` -- confirmed live that the
// naive version never became visible even during a real pkexec-triggered
// flow that genuinely reached this agent. Two things that pattern gets
// right that the naive version didn't:
//   1. `visible` binds to `isActive`, not `flow !== null`.
//   2. UI state is a local snapshot (currentMessage, responseRequired, ...)
//      refreshed via `Connections { target: flow }` on each of the flow's
//      own *Changed signals, rather than binding Text.text etc. directly to
//      `flow.message` and friends.
// Root cause of why the direct-binding version silently never fired is
// still unconfirmed; this follows the proven pattern instead of
// re-deriving it.
//
// Same overlay convention as Launcher.qml otherwise: full-screen anchors +
// exclusiveZone 0 + Overlay layer + transparent + click-outside backdrop +
// focusable true (this window takes keyboard input, unlike the hover
// popups which deliberately use grabFocus: false).
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
        // Must happen before submit() -- an unset selectedIdentity fails
        // every submission with "Not authorized" regardless of what's
        // typed, since polkit then has no identity to check the response
        // against. This machine only ever has one real admin user, so
        // picking identities[0] unconditionally is correct here; a
        // multi-admin box would need an actual picker UI instead.
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

    // Re-targets automatically whenever PolkitAgentService.flow changes to
    // a new object -- `target:` is itself a live binding.
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
        // A failed attempt (wrong password/fingerprint) keeps
        // isResponseRequired true for the retry, so the isResponseRequired
        // handler's clear-on-false never fires here -- clear explicitly so
        // a rejected password doesn't linger in the field.
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
            // Swallows clicks so they don't fall through to the cancel
            // backdrop above.
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
                // \u{} escape, not a literal glyph byte -- this codepoint
                // range silently corrupted to an empty string when written
                // raw earlier in this repo's history (see FilesTree.qml's
                // chevron comment for the original incident).
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
