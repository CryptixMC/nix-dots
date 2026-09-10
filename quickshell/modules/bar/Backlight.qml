import QtQuick
import Quickshell.Io

// Mirrors waybar's "backlight" module (icons 1:1 from waybar.nix).
// FileView + watchChanges instead of polling brightnessctl — as a side
// effect this also live-updates from the XF86MonBrightness{Up,Down}
// hardware-key binds in hyprland.nix, for free.
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

    // Waybar keeps this tooltip plain-text (GTK's set_tooltip_text(), not
    // _markup()) to dodge pango tags rendering literally — that constraint
    // doesn't apply to a QML-rendered popup, so it gets the same styling
    // as the others.
    tooltipTitle: "BRIGHTNESS"
    tooltipBody: `${percent}%`
}
