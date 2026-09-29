import QtQuick
import Quickshell.Services.Mpris
import "../../theme"
import "popups"

// Bar widget for the active MPRIS player; hidden when no player exists.
// implicitWidth binds to the Row's own implicitWidth: a hand-summed width
// undersized and let the next module overlap it.
Item {
    id: root

    readonly property var activePlayer: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) ?? Mpris.players.values[0] ?? null
    visible: root.activePlayer !== null

    implicitWidth: root.visible ? content.implicitWidth : 0
    implicitHeight: Theme.spacing.barIconHitSize

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Shows the next action (pause while playing), matching
            // QuickSettingsPanel. Click opens the popup; scroll skips tracks.
            text: (root.activePlayer?.isPlaying ?? false) ? "\u{F03E4}" : "\u{F040A}"
            renderType: Text.NativeRendering
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
            color: hoverArea.containsMouse ? Theme.color.purpleHover : Theme.color.accentPurple

            Behavior on color {
                ColorAnimation { duration: Theme.motion.hoverColor.duration; easing.type: Theme.motion.hoverColor.easing }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Theme.spacing.mediaWidgetMaxLabelWidth)
            elide: Text.ElideRight
            text: {
                const p = root.activePlayer;
                if (!p)
                    return "";
                return p.trackArtist ? `${p.trackArtist} - ${p.trackTitle}` : p.trackTitle;
            }
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
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible
        onWheel: wheel => {
            if (!root.activePlayer)
                return;
            if (wheel.angleDelta.y > 0)
                root.activePlayer.next();
            else if (wheel.angleDelta.y < 0)
                root.activePlayer.previous();
        }
    }

    MediaPopup {
        id: popup
        anchorItem: root
        player: root.activePlayer
    }
}
