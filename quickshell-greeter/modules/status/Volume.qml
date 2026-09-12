import QtQuick
import Quickshell.Services.Pipewire
import "../../theme"

// Trimmed adaptation of quickshell/modules/bar/Volume.qml — read-only
// status here, no click-to-open flyout (nothing meaningful to change from
// a pre-login screen).
Row {
    id: root
    spacing: 6

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volumePct: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property var icons: ["󰕿", "󰖀", "󰕾"]

    // Sink audio properties are only valid once bound via PwObjectTracker —
    // same requirement as the bar's Volume.qml.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "󰝟" : root.icons[Math.min(root.icons.length - 1, Math.floor(root.volumePct / (100 / root.icons.length)))]
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "muted" : `${root.volumePct}%`
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
