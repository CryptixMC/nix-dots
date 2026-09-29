import QtQuick
import Quickshell
import "../../theme"

// Right-side module icon: glyph, hover color, optional click/scroll
// action and hover popup.
Item {
    id: root

    property string glyph: ""
    property color glyphColorOverride: "transparent"
    // Optional custom glyph content for marks that aren't a font codepoint
    // (e.g. QubiStatus's vector drawing).
    property Component glyphComponent: null
    property string clickCommand: ""
    property string scrollUpCommand: ""
    property string scrollDownCommand: ""
    // For modules whose click action is in-process state (e.g. a DND
    // toggle) rather than a shell command.
    property var onClickFn: null

    property string tooltipTitle: ""
    property string tooltipBody: ""
    property string tooltipMuted: ""

    // Default popup is a hover ModuleTooltip; modules can supply their own
    // Component without touching the hover/timer plumbing.
    property Component popupComponent: Component {
        ModuleTooltip {
            anchor.item: root
            titleText: root.tooltipTitle
            bodyText: root.tooltipBody
            mutedText: root.tooltipMuted
        }
    }
    readonly property alias popupItem: popupLoader.item
    // Set false for click-driven popups and drive popupItem.visible yourself.
    property bool popupOpensOnHover: true

    implicitWidth: Theme.spacing.barIconHitSize
    implicitHeight: Theme.spacing.barIconHitSize

    Loader {
        anchors.centerIn: parent
        active: root.glyphComponent !== null
        sourceComponent: root.glyphComponent
    }

    Text {
        anchors.centerIn: parent
        visible: root.glyphComponent === null
        text: root.glyph
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeBase
        // These Nerd Font icons live above U+FFFF; Qt's default distance-field
        // renderer draws them as blurry emoji fallbacks, NativeRendering doesn't.
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

        onEntered: if (root.popupOpensOnHover && root.tooltipTitle.length > 0)
            hoverTimer.restart()
        onExited: {
            hoverTimer.stop();
            if (root.popupOpensOnHover && root.popupItem)
                root.popupItem.visible = false;
        }
    }

    Timer {
        id: hoverTimer
        interval: Theme.motion.tooltipHoverDelayMs
        onTriggered: if (root.popupItem)
            root.popupItem.visible = true
    }

    Loader {
        id: popupLoader
        active: true
        sourceComponent: root.popupComponent
    }
}
