import QtQuick
import Quickshell
import "../../theme"

// Shared hover tooltip for right-side bar icons. Caller sets `anchor.item`
// to its own root Item and drives `visible` from its own hover state —
// this component only owns styling/layout, not when it's shown.
// No drop-shadow (waybar's CSS has one): would need an unconfirmed Qt
// effects module for a purely cosmetic detail, not worth the risk here.
PopupWindow {
    id: root

    property string titleText: ""
    property string bodyText: ""
    property string mutedText: ""

    implicitWidth: Math.max(Theme.spacing.tooltipMinWidth, content.implicitWidth + Theme.spacing.tooltipPadX)
    implicitHeight: content.implicitHeight + Theme.spacing.tooltipPadY
    color: "transparent"
    visible: false
    grabFocus: false

    anchor {
        edges: Edges.Bottom
        gravity: Edges.Bottom
        adjustment: PopupAdjustment.Slide
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        Column {
            id: content
            anchors.centerIn: parent
            spacing: Theme.spacing.tooltipLineGap

            Text {
                visible: root.titleText.length > 0
                text: root.titleText
                color: Theme.color.accentPurple
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
                font.bold: Theme.font.weightBold
            }

            Text {
                visible: root.bodyText.length > 0
                text: root.bodyText
                color: Theme.color.tooltipFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                visible: root.mutedText.length > 0
                text: root.mutedText
                color: Theme.color.tooltipMuted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }
        }
    }
}
