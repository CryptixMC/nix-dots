import QtQuick
import Quickshell.Io
import "../../theme"

// CPU temperature module. Polls every 5s: there is no Quickshell
// temperature service and sysfs temp files don't reliably fire inotify.
BarIcon {
    id: root

    // Fallback path; hwmon numbering isn't stable across reboots, so the
    // real coretemp path is resolved at startup below.
    property string tempPath: "/sys/class/thermal/thermal_zone6/temp"

    readonly property var icons: ["󱃃", "󰔏", "󱃂"]
    readonly property real tempC: (parseInt(tempFile.text()) || 0) / 1000
    readonly property bool isCritical: tempC >= 80

    Process {
        running: true
        command: ["sh", "-c", "grep -l coretemp /sys/class/hwmon/hwmon*/name 2>/dev/null | head -n1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.length > 0)
                    root.tempPath = line.replace(/\/name$/, "") + "/temp1_input";
            }
        }
    }

    FileView {
        id: tempFile
        path: root.tempPath
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: tempFile.reload()
    }

    glyph: isCritical ? "󰸁" : icons[Math.min(icons.length - 1, Math.floor(tempC / (100 / icons.length)))]
    glyphColorOverride: isCritical ? Theme.color.accentPink : "transparent"

    CriticalBlink on opacity {
        running: root.isCritical
    }

    tooltipTitle: "CPU TEMP"
    tooltipBody: `${Math.round(tempC)}°C`
}
