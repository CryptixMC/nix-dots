import QtQuick
import "../../services"
import "../../theme"

// rx/tx throughput -- SystemStats.netRxBps/netTxBps were already computed
// for the wallpaper's own readout and had no bar consumer until now
// (Network.qml's own header comment flags this exact gap: no bandwidth
// rate property, custom byte-counter diffing "wasn't judged worth it" --
// it already existed one file over).
//
// implicitWidth binds to the content Row's OWN implicitWidth (a real
// Qt-computed sum, read back after layout) rather than a hand-summed
// guess -- the hand-summed version undersized the module and let the next
// bar module render on top of the tail of this one's text (confirmed
// live). Root can't just BE the Row (Tray.qml's simpler convention)
// because this module also needs a MouseArea that anchors.fill's the
// whole hit area, which Row explicitly forbids for its own children.
//
// Acquires the base polling tier for the bar's own lifetime (mounted once,
// never torn down) rather than per-hover -- symmetric acquire/release
// still included for cleanliness, matching every other SystemStats
// consumer's convention, even though in practice release() never fires
// before the process exits.
Item {
    id: root

    implicitWidth: content.implicitWidth
    implicitHeight: Theme.spacing.barIconHitSize

    Component.onCompleted: SystemStats.acquire()
    Component.onDestruction: SystemStats.release()

    function fmt(bps) {
        if (bps < 1024)
            return `${Math.round(bps)}B`;
        if (bps < 1024 * 1024)
            return `${(bps / 1024).toFixed(0)}K`;
        return `${(bps / (1024 * 1024)).toFixed(1)}M`;
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 3

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0A46}" // md-swap_vertical
            renderType: Text.NativeRendering
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            color: hoverArea.containsMouse ? Theme.color.purpleHover : Theme.color.rightModuleFg

            Behavior on color {
                ColorAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `${root.fmt(SystemStats.netRxBps)}/${root.fmt(SystemStats.netTxBps)}`
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            color: hoverArea.containsMouse ? Theme.color.purpleHover : Theme.color.rightModuleFg

            Behavior on color {
                ColorAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: hoverTimer.restart()
        onExited: {
            hoverTimer.stop();
            tooltip.visible = false;
        }
    }

    Timer {
        id: hoverTimer
        interval: Theme.motion.tooltipHoverDelayMs
        onTriggered: tooltip.visible = true
    }

    ModuleTooltip {
        id: tooltip
        anchor.item: root
        titleText: "NETWORK SPEED"
        bodyText: `↓ ${(SystemStats.netRxBps / 1e6).toFixed(2)} MB/s   ↑ ${(SystemStats.netTxBps / 1e6).toFixed(2)} MB/s`
    }
}
