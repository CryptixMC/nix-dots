import QtQuick
import "../../theme"

// Shared critical-state blink.
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
