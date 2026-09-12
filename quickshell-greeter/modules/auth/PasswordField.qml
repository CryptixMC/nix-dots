import QtQuick
import "../../theme"

// Styled the same way as the app launcher's search field
// (quickshell/modules/launcher/Launcher.qml) for visual consistency with
// the rest of the desktop, without importing that file directly (see
// theme/Colors.qml's decoupling note).
Rectangle {
    width: parent.width
    height: 40
    radius: 6
    color: Colors.inputBg
    border.width: 1
    border.color: Colors.inputBorder

    Text {
        visible: input.text.length === 0
        anchors {
            left: parent.left
            leftMargin: 12
            verticalCenter: parent.verticalCenter
        }
        text: AuthState.prompt.length > 0 ? AuthState.prompt : "Password"
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }

    TextInput {
        id: input
        anchors {
            fill: parent
            margins: 11
        }
        color: Colors.fg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
        echoMode: AuthState.maskInput ? TextInput.Password : TextInput.Normal
        enabled: AuthState.phase !== AuthState.phaseAuthenticating && AuthState.phase !== AuthState.phaseLaunching

        onAccepted: {
            if (text.length === 0)
                return;
            AuthState.submit(text);
            text = "";
        }

        // Cancels the in-flight session and starts a fresh one, so the
        // field never gets stuck on a dead conversation.
        Keys.onEscapePressed: AuthState.retry()
    }

    Component.onCompleted: input.forceActiveFocus()
}
