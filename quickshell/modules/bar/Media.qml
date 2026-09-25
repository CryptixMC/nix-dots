import QtQuick
import Quickshell.Services.Mpris
import "../../theme"

// Dedicated bar surface for the active MPRIS player -- distinct from
// QuickSettingsPanel's compact embedded media card (that one's a
// convenience inside an already-open panel; this is the glanceable
// always-there version Spotify etc actually earns a bar slot for). Only
// present in the layout at all when a player exists (RightModules.qml
// binds `visible`), so a machine with nothing playing doesn't carry a
// permanently-empty module.
//
// implicitWidth binds to the content Row's own implicitWidth, not a
// hand-summed guess -- see NetSpeed.qml's header for why (a hand-summed
// version undersized itself and got overlapped by the next bar module,
// confirmed live earlier this session).
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
            // md-pause while playing / md-play while paused -- the standard
            // media-transport-button convention (always shows the NEXT
            // action, not current state), matching QuickSettingsPanel's own
            // transport button glyph for visual consistency between the
            // two, even though clicking THIS glyph opens the popup rather
            // than toggling directly (scrolling over the widget skips to
            // the previous/next track instead, see the MouseArea below).
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
