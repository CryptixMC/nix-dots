import QtQuick
import Quickshell.Io
import "../../theme"

// Read-only backlight status. Unverified whether the greeter user can read the
// sysfs value; parseInt(...) || 0 degrades to "0%" if not.
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
        color: Colors.textBody
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeLarge
        renderType: Text.NativeRendering
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${root.percent}%`
        color: Colors.textBody
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeBase
    }
}
