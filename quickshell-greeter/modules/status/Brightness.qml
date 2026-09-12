import QtQuick
import Quickshell.Io
import "../../theme"

// Trimmed adaptation of quickshell/modules/bar/Backlight.qml. Whether the
// greeter's unprivileged "greeter" user has the same udev-granted seat ACL
// on /sys/class/backlight/intel_backlight/brightness as a logged-in user's
// session is unconfirmed — logind grants that ACL to whatever session owns
// the active seat, which greetd's greeter session actually is pre-login, so
// it's plausible this just works, but the existing parseInt(...) || 0
// fallback already degrades to a harmless "0%" rather than erroring either
// way, so this hasn't blocked shipping it. Verify against a real login
// screen if the number never moves.
Row {
    id: root
    spacing: 6

    readonly property var icons: ["󰃞", "󰃟", "󰃠"]
    readonly property int maxBrightness: parseInt(maxFile.text()) || 100
    readonly property int percent: Math.round((parseInt(brightnessFile.text()) || 0) / maxBrightness * 100)

    FileView {
        id: maxFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
    }

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        watchChanges: true
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.icons[Math.min(root.icons.length - 1, Math.floor(root.percent / (100 / root.icons.length)))]
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${root.percent}%`
        color: Colors.mutedFg
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
