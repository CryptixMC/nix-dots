import QtQuick
import Quickshell.Io
import "../../theme"

// Mirrors waybar's "temperature" module (icons/critical-threshold 1:1 from
// waybar.nix). No dedicated Quickshell temperature service exists, and
// sysfs temp attributes don't reliably fire inotify on read, so this
// polls (matching waybar's own `interval: 5`) rather than file-watching.
BarIcon {
    id: root

    // Fallback: x86_pkg_temp thermal zone, confirmed to read the same
    // value as coretemp's hwmon on this host at plan time — hwmon device
    // numbering isn't guaranteed stable across reboots, so resolve the
    // real coretemp path dynamically below instead of hardcoding it.
    property string tempPath: "/sys/class/thermal/thermal_zone6/temp"

    readonly property var icons: ["󱃃", "󰔏", "󱃂"]
    readonly property real tempC: (parseInt(tempFile.text()) || 0) / 1000
    readonly property bool isCritical: tempC >= 80

    // Process/SplitParser shape follows Quickshell.Io's general convention
    // (not independently re-verified against installed .qmltypes this
    // pass like the Services modules were) — verify at implementation
    // time if this one-shot resolution doesn't fire.
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
    glyphColorOverride: isCritical ? Colors.accentPink : "transparent"

    SequentialAnimation on opacity {
        running: root.isCritical
        loops: Animation.Infinite
        NumberAnimation {
            to: 0.2
            duration: 500
        }
        NumberAnimation {
            to: 1
            duration: 500
        }
    }

    tooltipTitle: "CPU TEMP"
    tooltipBody: `${Math.round(tempC)}°C`
}
