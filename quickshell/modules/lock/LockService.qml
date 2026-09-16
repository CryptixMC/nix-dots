pragma Singleton
import QtQuick
import Quickshell.Wayland
import Quickshell.Services.Pam

// Lock-screen auth state, driving `PamContext` directly (not
// Quickshell.Services.Greetd — that's greetd's own pre-login session
// protocol, a different thing entirely) against the "quickshell-lock" PAM
// service declared in modules/nixos/services/quickshell-lock.nix. Structure
// mirrors quickshell-greeter/modules/auth/AuthState.qml's phase machine
// (idle/prompting/authenticating/failed) — same shape, different backend,
// since this repo already has one proven-live PAM-conversation pattern to
// follow instead of guessing at PamContext's calling convention from docs
// alone.
//
// NOT WIRED TO ANY TRIGGER. Nothing calls lock() from a keybind, idle
// timeout, or `loginctl lock-session` handler yet — the only way to
// exercise this at all is the IpcHandler in LockView.qml
// (`quickshell ipc call lock lock`), run deliberately by hand. A broken
// unlock path here has real consequences (stuck at a lock screen with no
// way back in), so this stays inert-but-complete until it's been tested
// that way at least once — see TODO.md §5.
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

        // One WlSessionLockSurface is instantiated per screen automatically
        // (ext-session-lock-v1 semantics) — LockView is parented explicitly
        // onto the surface's own `contentItem` rather than declared as a
        // direct child, since WlSessionLockSurface's default property is
        // generic `data`, not necessarily normal Item-anchoring semantics.
        // UNVERIFIED beyond what the qmltypes declare — no live example of
        // this exact wiring existed locally to copy from; confirm the lock
        // surface actually renders on the first real test.
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

        // PamContext.onMessage/onCompleted/onError are plain methods to
        // override (qmltypes lists them under `Method`, not `Signal`) — NOT
        // QML signal-handler properties. `onMessage: (...) => {}` silently
        // fails to bind ("Cannot assign to non-existent property") and
        // takes the WHOLE shell.qml down with it, since this is a required
        // singleton import. Confirmed against
        // quickshell-service-pam.qmltypes and matching the
        // `function onX(...) {}` convention AuthState.qml already uses
        // for its own callbacks.
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
                // Immediately start a fresh attempt so the field is usable
                // again — mirrors the "don't strand the user on a dead
                // conversation" concern AuthState.qml documents for
                // greetd's create_session/cancelSession dance. UNVERIFIED:
                // whether PamContext.start() can just be called again
                // directly after a Failed completion, or needs
                // `active = false` toggled first to reset internal state —
                // PamContext's own `active` property is writable, which
                // suggests it might. Confirm this on the very first real
                // test (a deliberately wrong password) before trusting it.
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
