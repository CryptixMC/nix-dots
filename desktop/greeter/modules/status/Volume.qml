import QtQuick
import Quickshell.Services.Pipewire
import "../../theme"

// Read-only volume status.
Row {
    id: root
    spacing: 6

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volumePct: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property var icons: ["󰕿", "󰖀", "󰕾"]

    // Sink audio properties are only valid once bound via PwObjectTracker.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "󰝟" : root.icons[Math.min(root.icons.length - 1, Math.floor(root.volumePct / (100 / root.icons.length)))]
        color: Colors.textBody
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "muted" : `${root.volumePct}%`
        color: Colors.textBody
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
