pragma Singleton
import QtQuick
import Quickshell.Wayland
import Quickshell.Services.Pam

// Lock-screen auth state: drives PamContext against the "quickshell-lock" PAM
// service (modules/nixos/services/quickshell-lock.nix).
// Deliberately not wired to any keybind/idle trigger until the unlock path is
// tested by hand via `quickshell ipc call lock lock` (TODO.md §5).
QtObject {
    id: root

    readonly property string phaseIdle: "idle"
    readonly property string phasePrompting: "prompting"
    readonly property string phaseAuthenticating: "authenticating"
    readonly property string phaseFailed: "failed"

    property string phase: phaseIdle
    property string prompt: ""
    property bool maskInput: true
    property string errorMessage: ""

    property WlSessionLock sessionLock: WlSessionLock {
        onLockStateChanged: if (!locked)
            root.reset()

        // One surface per screen. LockView is parented to contentItem because the
        // surface's default property is generic `data` (unverified on a live session).
        surface: Component {
            WlSessionLockSurface {
                id: surface
                color: "transparent"

                LockView {
                    parent: surface.contentItem
                    anchors.fill: parent
                    lockSurface: surface
                }
            }
        }
    }

    readonly property PamContext pam: PamContext {
        config: "quickshell-lock"
        user: "cryptix"

        // onMessage/onCompleted/onError are methods, not signals: use
        // `function onX() {}`; `onX: ...` fails to load and breaks the whole shell.
        function onMessage(message, isError, responseRequired, responseVisible) {
            root.prompt = message;
            root.maskInput = responseRequired && !responseVisible;
            root.phase = responseRequired ? root.phasePrompting : root.phaseAuthenticating;
            if (isError)
                root.errorMessage = message;
        }

        function onCompleted(result) {
            if (result === PamResult.Success) {
                root.sessionLock.locked = false;
            } else {
                root.errorMessage = "authentication failed";
                root.phase = root.phaseFailed;
                // Restart so the field stays usable. Unverified whether start()
                // works directly after a failure or needs `active = false` first.
                pam.start();
            }
        }

        function onError(error) {
            root.errorMessage = "PAM error — see journalctl";
            root.phase = root.phaseFailed;
        }
    }

    function reset() {
        pam.abort();
        phase = phaseIdle;
        prompt = "";
        errorMessage = "";
    }

    function lock() {
        if (sessionLock.locked)
            return;
        sessionLock.locked = true;
        errorMessage = "";
        pam.start();
    }

    function submit(response) {
        if (phase !== phasePrompting)
            return;
        phase = phaseAuthenticating;
        pam.respond(response);
    }
}
