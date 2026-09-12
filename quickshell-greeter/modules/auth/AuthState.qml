pragma Singleton
import QtQuick
import Quickshell.Services.Greetd

// Wraps Quickshell's built-in Greetd singleton (Quickshell.Services.Greetd)
// with UI-friendly state for the password-only v1 flow. Fingerprint at the
// greeter is explicitly out of scope — greetd's create_session/
// post_auth_message_response conversation happens inside greetd's own
// process as a single sequential PAM stack, so a second concurrent
// PamContext driven from this QML would just be a fake dialog disconnected
// from the actual login decision. Session/user are both fixed (Config.qml/
// SessionCommand.qml) rather than enumerated at runtime.
//
// Root is a Connections targeting Greetd directly — same "extend a non-
// QtObject root type" pattern as UsageStore.qml's FileView root in the
// main quickshell/ shell — rather than a QtObject wrapping a nested
// Connections child, which would need an extra named-property indirection
// for no benefit.
Connections {
    id: root
    target: Greetd

    readonly property string phaseIdle: "idle"
    readonly property string phasePrompting: "prompting"
    readonly property string phaseAuthenticating: "authenticating"
    readonly property string phaseFailed: "failed"
    readonly property string phaseLaunching: "launching"

    property string phase: phaseIdle
    property string prompt: ""
    // authMessage's responseRequired+echoResponse pair distinguishes a
    // password-style prompt (mask) from a visible-echo one (e.g. an OTP
    // token) — mirrors the same decoding already used for Quickshell's
    // PamContext elsewhere in this repo's research.
    property bool maskInput: true
    property string errorMessage: ""

    // True only for the lifetime of one explicit create_session attempt —
    // from start() until it resolves via authFailure/error/readyToLaunch.
    // Confirmed via VM testing: after a failed attempt, Quickshell's Greetd
    // backend keeps emitting authMessage/error signals from what looks
    // like an internal reconnect loop ("unable to send message: Connection
    // refused" repeating with no corresponding new attempt in `journalctl
    // -u greetd`). Without this guard, those stray post-failure signals
    // kept re-flipping phase back to phaseAuthenticating, which disables
    // PasswordField's TextInput (including its Keys.onEscapePressed retry
    // shortcut) — the field looked permanently stuck after one wrong
    // password, with neither further typing nor Escape doing anything.
    property bool sessionLive: false
    // Set by submit() when there's no live conversation to respond to
    // (typing a fresh password and hitting Enter right after a failure,
    // without pressing Escape first) — greetd requires a brand new
    // create_session before it'll accept another post_auth_message_response,
    // so submit() transparently retries and this value gets sent as soon
    // as the new session's password prompt actually arrives, instead of
    // requiring the user to notice the dead end and press Escape manually.
    property string pendingResponse: ""

    function start() {
        errorMessage = "";
        phase = phaseAuthenticating;
        sessionLive = true;
        Greetd.createSession(Config.username);
    }

    function submit(response) {
        if (root.sessionLive && root.phase === root.phasePrompting) {
            root.phase = root.phaseAuthenticating;
            Greetd.respond(response);
        } else {
            root.pendingResponse = response;
            root.retry();
        }
    }

    function retry() {
        Greetd.cancelSession();
        start();
    }

    // Greetd.available is false whenever GREETD_SOCK isn't set — true only
    // when actually running under greetd (Phase 1+ of the plan, not
    // Phase 0's in-session standalone render).
    Component.onCompleted: if (Greetd.available)
        start()

    // fprintd's own PAM prompt ("Place your right index finger on the
    // fingerprint reader" or similar, wording varies by reader/driver) runs
    // well past PasswordField's width — substituting a short display string
    // keyed on a case-insensitive "finger" match sidesteps needing to match
    // fprintd's exact wording. modules/nixos/services/fprintd.nix sets
    // `security.pam.services.greetd.fprintAuth = false`, so this message
    // arriving here at all was a little surprising — worth re-checking
    // during VM verification, but the short-text fix stands regardless of
    // why the prompt shows up.
    function shortPromptFor(message) {
        return message.toLowerCase().includes("finger") ? "Scan fingerprint" : message;
    }

    function onAuthMessage(message, error, responseRequired, echoResponse) {
        if (!root.sessionLive)
            return;
        root.prompt = root.shortPromptFor(message);
        root.maskInput = responseRequired && !echoResponse;
        if (responseRequired && root.pendingResponse.length > 0) {
            const resp = root.pendingResponse;
            root.pendingResponse = "";
            root.phase = root.phaseAuthenticating;
            Greetd.respond(resp);
            return;
        }
        root.phase = responseRequired ? root.phasePrompting : root.phaseAuthenticating;
        if (error)
            root.errorMessage = message;
    }

    function onAuthFailure(message) {
        if (!root.sessionLive)
            return;
        root.sessionLive = false;
        root.pendingResponse = "";
        root.errorMessage = message;
        root.phase = root.phaseFailed;
    }

    function onReadyToLaunch() {
        if (!root.sessionLive)
            return;
        root.sessionLive = false;
        root.phase = root.phaseLaunching;
        Greetd.launch(SessionCommand.argv, SessionCommand.environment);
    }

    function onError(error) {
        if (!root.sessionLive)
            return;
        root.sessionLive = false;
        root.pendingResponse = "";
        root.errorMessage = error;
        root.phase = root.phaseFailed;
    }
}
