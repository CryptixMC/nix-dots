import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../theme"

// Transient centred overlay for volume/mic/brightness changes. Full-screen,
// Overlay layer, non-focusable, auto-dismissing.
//
// Changes are detected via the computed properties' on<Prop>Changed
// handlers, which re-track automatically if the default sink/source
// changes. The initial evaluation doesn't fire them, so nothing flashes
// on launch.
PanelWindow {
    id: root

    screen: Quickshell.screens[0] ?? null
    visible: hideTimer.running
    focusable: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.sink, root.source].filter(o => o !== null && o !== undefined)
    }

    property string kind: "volume" // "volume" | "mic" | "brightness"
    property real value: 0
    property bool muted: false

    Timer {
        id: hideTimer
        interval: 1400
    }

    function trigger(k, v, m) {
        root.kind = k;
        root.value = v;
        root.muted = m ?? false;
        hideTimer.restart();
    }

    readonly property real volumeValue: root.sink?.audio?.volume ?? 0
    readonly property bool volumeMuted: root.sink?.audio?.muted ?? false
    onVolumeValueChanged: root.trigger("volume", root.volumeValue, root.volumeMuted)
    onVolumeMutedChanged: root.trigger("volume", root.volumeValue, root.volumeMuted)

    readonly property real micValue: root.source?.audio?.volume ?? 0
    readonly property bool micMuted: root.source?.audio?.muted ?? false
    onMicValueChanged: root.trigger("mic", root.micValue, root.micMuted)
    onMicMutedChanged: root.trigger("mic", root.micValue, root.micMuted)

    FileView {
        id: maxBrightnessFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
    }
    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        watchChanges: true
    }
    readonly property int maxBrightness: parseInt(maxBrightnessFile.text()) || 100
    readonly property real brightnessValue: (parseInt(brightnessFile.text()) || 0) / root.maxBrightness
    onBrightnessValueChanged: root.trigger("brightness", root.brightnessValue, false)

    readonly property string glyph: {
        if (root.kind === "mic")
            return root.muted ? "\u{F036D}" : "\u{F036C}"; // md-microphone_off / md-microphone
        if (root.kind === "brightness")
            return "\u{F00DF}"; // md-brightness_6
        return root.muted ? "\u{F075F}" : "\u{F057E}"; // md-volume_mute / md-volume_high
    }
    readonly property string label: root.kind === "mic" ? "MIC" : root.kind === "brightness" ? "BRIGHTNESS" : "VOLUME"

    Rectangle {
        anchors.centerIn: parent
        width: Theme.spacing.osdWidth
        height: Theme.spacing.osdHeight
        radius: Theme.radius.popup
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        opacity: root.visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.motion.hoverColor.duration }
        }

        Row {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: Theme.spacing.osdPadX
            }
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                renderType: Text.NativeRendering
                font.family: Theme.font.family
                font.pixelSize: Theme.spacing.osdIconSize
                // One colour regardless of mute; the glyph shape already
                // signals mute (matches QuickSettingsPanel's sliders).
                color: Theme.color.accentPurple
            }

            Column {
                width: parent.width - Theme.spacing.osdIconSize - 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    text: root.label
                    color: Theme.color.tooltipMuted
                    font.family: Theme.font.family
                    font.pixelSize: 9
                    font.bold: true
                }

                Item {
                    width: parent.width
                    height: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: Theme.radius.sliderTrack
                        color: Theme.color.sliderTrackBg
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * Math.min(1, Math.max(0, root.value))
                        height: 6
                        radius: Theme.radius.sliderTrack
                        color: Theme.color.accentPurple
                    }
                }
            }
        }
    }
}
