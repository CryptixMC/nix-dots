import QtQuick
import Quickshell.Io

// Backlight module. FileView with watchChanges instead of polling, which
// also picks up changes from the brightness hardware keys.
BarIcon {
    id: root

    readonly property var icons: ["󰃞", "󰃟", "󰃠"]

    FileView {
        id: maxFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
    }

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        watchChanges: true
    }

    readonly property int maxBrightness: parseInt(maxFile.text()) || 100
    readonly property int percent: Math.round((parseInt(brightnessFile.text()) || 0) / maxBrightness * 100)

    glyph: icons[Math.min(icons.length - 1, Math.floor(percent / (100 / icons.length)))]

    scrollUpCommand: "brightnessctl set +5%"
    scrollDownCommand: "brightnessctl set 5%-"

    tooltipTitle: "BRIGHTNESS"
    tooltipBody: `${percent}%`
}
