import QtQuick
import Quickshell
import "core"
import "chat"
import "sessions"
import "modelbrowser"
import "extensions"
import "clipboard"
import "askuser"
import "screenctx"
import "voice"
import "notes"

// Everything Qubi puts on screen, as one component a host shell drops into
// its ShellRoot:
//
//   import "modules/qubi/qml"
//   Qubi { theme: Theme }
//
// Each overlay owns its own IpcHandler; the target names (chat, sessions,
// modelbrowser, extensions, clipboard, askuser, screenctx, voice, notes,
// qubi-model) are a stable interface -- see docs/protocol.md.
Scope {
    id: root

    // The host's theme object, or null to run on QubiTheme's defaults. See
    // core/QubiTheme.qml for the (small, all-optional) shape it reads.
    property var theme: null
    // Host overrides for core/QubiConfig.qml, e.g. ({ defaultCwd: "/src" }).
    property var config: ({})
    // Set an entry to false to leave that overlay out entirely. `chat` and
    // `askuser` are not optional: chat is the product, and the engine's
    // ask-user MCP server blocks on the askuser dialog.
    property var features: ({})

    function _on(name) {
        return root.features[name] !== false;
    }

    Binding {
        target: QubiTheme
        property: "host"
        value: root.theme
    }
    Binding {
        target: QubiConfig
        property: "overrides"
        value: root.config
    }

    ChatOverlay {}
    AskUserDialog {}

    LazyLoader {
        active: root._on("compare")
        ChatCompare {}
    }
    LazyLoader {
        active: root._on("sessions")
        SessionsPicker {}
    }
    LazyLoader {
        active: root._on("modelbrowser")
        ModelBrowser {}
    }
    LazyLoader {
        active: root._on("extensions")
        ExtensionsManager {}
    }
    LazyLoader {
        active: root._on("clipboard")
        ClipboardTransform {}
    }
    LazyLoader {
        active: root._on("screenctx")
        ScreenContext {}
    }
    LazyLoader {
        active: root._on("voice")
        VoiceOverlay {}
    }
    LazyLoader {
        active: root._on("notes")
        NotesCapture {}
    }
}
