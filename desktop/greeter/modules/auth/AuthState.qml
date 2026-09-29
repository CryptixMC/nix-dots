pragma Singleton
import QtQuick
import Quickshell.Services.Greetd

// Wraps Quickshell's Greetd with UI state for a password-only flow.
// No fingerprint here: greetd runs one sequential PAM stack, so a separate
// PamContext would be disconnected from the real login decision.
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
    // Masked for password prompts, visible for echo prompts (e.g. OTP).
    property bool maskInput: true
    property string errorMessage: ""

    // True only during one create_session attempt. After a failure the Greetd
    // backend keeps emitting stray authMessage/error signals; without this guard
    // they re-disable the field and the greeter looks stuck.
    property bool sessionLive: false
    // Password typed after a failure, sent once the fresh session prompts
    // (greetd needs a new create_session before accepting another response).
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

// Greetd.available is false outside greetd (no GREETD_SOCK).
    Component.onCompleted: if (Greetd.available)
        start()

// Shortens fprintd's long "place your finger" prompt to fit the field.
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
