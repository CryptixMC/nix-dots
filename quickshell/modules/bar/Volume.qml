import QtQuick
import Quickshell.Services.Pipewire

// Mirrors waybar's "pulseaudio" module (icons 1:1 from waybar.nix), except
// click now opens a small volume flyout (VolumePopup.qml) instead of
// launching pavucontrol directly — pavucontrol is still one click away via
// the flyout's "›" button. Headset/headphone icon variants are skipped —
// no reliable signal to key off in this API, default icon array only.
BarIcon {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volumePct: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property var icons: ["󰕿", "󰖀", "󰕾"]

    // Sink audio properties are only valid once bound via PwObjectTracker.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    glyph: muted ? "󰝟" : icons[Math.min(icons.length - 1, Math.floor(volumePct / (100 / icons.length)))]

    onClickFn: () => popup.visible = !popup.visible
    scrollUpCommand: "pactl set-sink-volume @DEFAULT_SINK@ +5%"
    scrollDownCommand: "pactl set-sink-volume @DEFAULT_SINK@ -5%"

    tooltipTitle: "VOLUME"
    tooltipBody: muted ? "muted" : `${volumePct}%`
    tooltipMuted: sink?.description ?? ""

    VolumePopup {
        id: popup
        anchorItem: root
    }
}
