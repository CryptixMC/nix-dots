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

    implicitWidth: Math.max(138, content.implicitWidth + 22)
    implicitHeight: content.implicitHeight + 18
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
        color: Colors.tooltipBg
        border.color: Colors.tooltipBorder
        border.width: 1
        radius: 6

        Column {
            id: content
            anchors.centerIn: parent
            spacing: 2

            Text {
                visible: root.titleText.length > 0
                text: root.titleText
                color: Colors.accentPurple
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeSmall
                font.bold: true
            }

            Text {
                visible: root.bodyText.length > 0
                text: root.bodyText
                color: Colors.tooltipFg
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeSmall
            }

            Text {
                visible: root.mutedText.length > 0
                text: root.mutedText
                color: Colors.tooltipMuted
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeSmall
            }
        }
    }
}
