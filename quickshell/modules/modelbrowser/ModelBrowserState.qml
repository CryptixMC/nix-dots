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

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }
}
