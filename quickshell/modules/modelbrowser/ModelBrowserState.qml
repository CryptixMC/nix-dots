pragma Singleton
import QtQuick

// Show/hide state + the fetched model list for the model browser
// ("Cookbook" — browse llmfit-ranked Ollama models, click a card to pull).
// Kept minimal, same shape as SessionsState.qml: the list is refetched
// fresh from `llmfit recommend --json` every time the browser opens, not
// cached/persisted here.
//
// downloadProgress maps a model's ollama_name to an object
// {percent: number, status: string} while a pull is in flight for it —
// entries are removed once that model's pull completes or fails, so
// `downloadProgress[name] !== undefined` is the "currently downloading"
// check for a given card.
QtObject {
    id: root

    property bool visible: false
    property var models: []
    property bool loading: false
    property var downloadProgress: ({})

    // Everything Ollama already has locally, from qubi/installed_models.
    // Distinct from `models` (llmfit's *recommendation* feed, which is a
    // curated pull list and does not necessarily include what you have):
    // selecting an already-downloaded model must not depend on that feed
    // happening to mention it.
    property var installed: []
    property bool installedLoading: false

    // True when the browser was opened from the chat panel (tier picker's
    // "more models" row, or the hamburger menu's own entry point) meaning
    // "pick a model to use right now" — clicking an installed card then
    // calls GooseAcpSession.useModelNow() for the CURRENT conversation.
    // False means standalone browsing (SUPER+B / the "Browse Models"
    // hamburger entry): a catalogue only, clicking an installed card does
    // nothing (pulling an uninstalled one still works either way).
    //
    // Deliberately not "which tier to assign" (that concept no longer
    // exists here at all) — picking a model must never mutate a named
    // tier's configured model out from under every other conversation.
    property bool useMode: false

    function hideAndReset() {
        visible = false;
        useMode = false;
    }

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}
