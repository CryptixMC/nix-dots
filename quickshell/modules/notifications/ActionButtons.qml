import QtQuick
import "../../theme"

// A notification's action buttons, shared by the toast and the Notification
// Centre. "default" (a click on the body) and "inline-reply" (the reply
// field) are not buttons, so they are left out.
Flow {
    id: root

    property var notification: null

    readonly property var buttonActions: {
        const out = [];
        const all = root.notification?.actions ?? [];
        for (let i = 0; i < all.length; i++) {
            if (all[i].identifier !== "default" && all[i].identifier !== "inline-reply")
                out.push(all[i]);
        }
        return out;
    }

    visible: buttonActions.length > 0
    spacing: Theme.spacing.toastLineGap

    Repeater {
        model: root.buttonActions

        Rectangle {
            id: actionButton
            required property var modelData

            width: actionLabel.implicitWidth + 2 * Theme.spacing.toastCardInset
            height: actionLabel.implicitHeight + Theme.spacing.toastCardInset
            radius: Theme.radius.input
            color: actionArea.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
            border.width: Theme.spacing.borderHairline
            border.color: Theme.color.tooltipBorder

            Text {
                id: actionLabel
                anchors.centerIn: parent
                text: actionButton.modelData.text
                color: Theme.color.tooltipFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            MouseArea {
                id: actionArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: actionButton.modelData.invoke()
            }
        }
    }
}
