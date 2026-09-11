import QtQuick
import "../../theme"

// Shared "critical" blink animation — was a byte-for-byte duplicated
// SequentialAnimation on opacity in both Battery.qml and Temperature.qml.
// Usage: `CriticalBlink on opacity { running: root.isCritical }`.
SequentialAnimation {
    loops: Animation.Infinite

    NumberAnimation {
        to: Theme.motion.criticalBlink.dimTo
        duration: Theme.motion.criticalBlink.duration
    }
    NumberAnimation {
        to: Theme.motion.criticalBlink.restoreTo
        duration: Theme.motion.criticalBlink.duration
    }
}
