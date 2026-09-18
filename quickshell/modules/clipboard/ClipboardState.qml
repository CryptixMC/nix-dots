pragma Singleton
import QtQuick

// Global show/hide + transform state for the clipboard-transform overlay
// (SUPER+U). Structural cousin of LauncherState.qml/ModelBrowserState.qml.
QtObject {
    id: root

    property bool visible: false

    // phase drives which body ClipboardTransform.qml renders:
    // "checking" -> "picking" -> "running" -> "done"
    // or a terminal informational state: "empty" | "image" | "oversized" |
    // "gaming-blocked" | "error"
    property string phase: "checking"
    property string clipboardText: ""
    property string resultText: ""
    property string errorMessage: ""
    property string customPromptText: ""

    // Conservative cap on clipboard character count this feature will send
    // to a model — clipboard-transform is for quick snippets, not whole
    // documents, and this keeps a single request well inside even the
    // smallest routed model's safe context budget (see TODO.md §7's
    // OLLAMA_CONTEXT_LENGTH=16384 finding) without needing to know which
    // model is currently routed.
    readonly property int maxChars: 8000

    // Data-driven so adding an action later is one more list entry, not a
    // new code path (LauncherState.tabs' own convention). "custom" is
    // handled specially in ClipboardTransform.qml (shows a text field
    // instead of firing immediately).
    readonly property var actions: [
        { id: "summarize", label: "Summarize", glyph: "󰈔", prompt: "Summarize the following text concisely, preserving the key points:\n\n{{content}}" },
        { id: "markdown", label: "Reformat as Markdown", glyph: "󰍔", prompt: "Reformat the following text as clean, well-structured Markdown. Do not change the meaning or add content:\n\n{{content}}" },
        { id: "grammar", label: "Fix grammar", glyph: "󰗈", prompt: "Fix any spelling and grammar mistakes in the following text. Keep the original tone and meaning. Return only the corrected text:\n\n{{content}}" },
        { id: "explain", label: "Explain", glyph: "󰋗", prompt: "Explain the following text clearly, as if to someone unfamiliar with the topic:\n\n{{content}}" },
        { id: "translate", label: "Translate to English", glyph: "󰗊", prompt: "Translate the following text to English. Return only the translation:\n\n{{content}}" },
        { id: "concise", label: "Make concise", glyph: "󰅍", prompt: "Rewrite the following text to be as concise as possible while keeping all essential meaning:\n\n{{content}}" },
        { id: "actionitems", label: "Extract action items", glyph: "󰄵", prompt: "Extract a bullet list of concrete action items from the following text. If there are none, say so:\n\n{{content}}" },
        { id: "custom", label: "Custom prompt", glyph: "󰊄", prompt: "{{instruction}}:\n\n{{content}}" }
    ]

    function toggle() {
        visible = !visible;
    }

    function hide() {
        visible = false;
    }

    function reset() {
        phase = "checking";
        clipboardText = "";
        resultText = "";
        errorMessage = "";
        customPromptText = "";
    }
}
