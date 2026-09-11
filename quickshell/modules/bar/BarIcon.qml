import QtQuick
import Quickshell
import "../../theme"

// Right-side module icon: glyph + hover color + optional click/scroll
// action + hover tooltip. Was PlaceholderIcon.qml (static-only) in the
// first slice — renamed now that modules bind live glyphs/tooltips instead
// of static strings, same props otherwise since QML property bindings are
// reactive regardless of whether the source is a literal or an expression.
Item {
    id: root

    property string glyph: ""
    property color glyphColorOverride: "transparent"
    property string clickCommand: ""
    property string scrollUpCommand: ""
    property string scrollDownCommand: ""
    // For modules whose click action is in-process state (e.g. a DND
    // toggle) rather than a shell command.
    property var onClickFn: null

    property string tooltipTitle: ""
    property string tooltipBody: ""
    property string tooltipMuted: ""

    implicitWidth: Theme.spacing.barIconHitSize
    implicitHeight: Theme.spacing.barIconHitSize

    Text {
        anchors.centerIn: parent
        text: root.glyph
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeBase
        // Most of these Nerd Font icons (Material Design set) live above
        // U+FFFF, in the supplementary PUA-A plane — Qt's default
        // distance-field text renderer mis-rendered them as blurry color
        // emoji-fallback blobs even with the right font family loaded;
        // NativeRendering (FreeType/fontconfig path) renders them correctly.
        renderType: Text.NativeRendering
        color: root.glyphColorOverride.a > 0 ? root.glyphColorOverride : (mouseArea.containsMouse ? Theme.color.purpleHover : Theme.color.rightModuleFg)

        Behavior on color {
            ColorAnimation {
                duration: Theme.motion.hoverColor.duration
                easing.type: Theme.motion.hoverColor.easing
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        onClicked: {
            if (root.clickCommand.length > 0)
                Quickshell.execDetached(["sh", "-c", root.clickCommand]);
            if (root.onClickFn)
                root.onClickFn();
        }

        onWheel: wheel => {
            if (wheel.angleDelta.y > 0 && root.scrollUpCommand.length > 0)
                Quickshell.execDetached(["sh", "-c", root.scrollUpCommand]);
            else if (wheel.angleDelta.y < 0 && root.scrollDownCommand.length > 0)
                Quickshell.execDetached(["sh", "-c", root.scrollDownCommand]);
        }

        onEntered: if (root.tooltipTitle.length > 0)
            hoverTimer.restart()
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
        titleText: root.tooltipTitle
        bodyText: root.tooltipBody
        mutedText: root.tooltipMuted
    }
}
