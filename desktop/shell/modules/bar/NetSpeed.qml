import QtQuick
import "../../services"
import "../../theme"

// rx/tx throughput from SystemStats.
// implicitWidth binds to the Row's own implicitWidth: a hand-summed width
// undersized and let the next module overlap it. Root can't be the Row
// because the MouseArea must anchors.fill the whole module.
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
