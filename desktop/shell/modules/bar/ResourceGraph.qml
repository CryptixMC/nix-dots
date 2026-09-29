import QtQuick
import "../../services"
import "../../theme"
import "../common"

// CPU/RAM sparkline pair from SystemStats' history buffers.
// implicitWidth binds to the Row's own implicitWidth: a hand-summed width
// undersized and let the next module overlap it.
Item {
    id: root

    implicitWidth: content.implicitWidth
    implicitHeight: Theme.spacing.barIconHitSize

    Component.onCompleted: SystemStats.acquire()
    Component.onDestruction: SystemStats.release()

    function series(buf) {
        const out = [];
        for (let i = 0; i < SystemStats.histFill; i++)
            out.push(SystemStats.histAt(buf, i));
        return out;
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0EE0}" // md-chart_line
            renderType: Text.NativeRendering
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            color: hoverArea.containsMouse ? Theme.color.purpleHover : Theme.color.rightModuleFg

            Behavior on color {
                ColorAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
            }
        }

        Sparkline {
            anchors.verticalCenter: parent.verticalCenter
            values: root.series(SystemStats.histCpu)
            maxValue: 100
            color: Theme.color.accentPurple
            repaintTick: SystemStats.histSeq
        }

        Sparkline {
            anchors.verticalCenter: parent.verticalCenter
            values: root.series(SystemStats.histMem)
            maxValue: 100
            color: Theme.color.accentPink
            repaintTick: SystemStats.histSeq
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: `${SystemStats.cpuPercent.toFixed(0)}% ${(SystemStats.memUsedFrac * 100).toFixed(0)}%`
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
        titleText: "RESOURCES"
        bodyText: `CPU ${SystemStats.cpuPercent.toFixed(1)}%   RAM ${(SystemStats.memUsedFrac * 100).toFixed(1)}%`
        mutedText: `${(SystemStats.memUsedMiB / 1024).toFixed(1)} / ${(SystemStats.memTotalMiB / 1024).toFixed(1)} GiB`
    }
}
