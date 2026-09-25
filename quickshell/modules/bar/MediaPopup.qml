import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../theme"

// Full transport surface for Media.qml's bar module -- album art
// placeholder, title/artist, seek bar, prev/play-pause/next, and a player
// picker when more than one MPRIS player is registered. Same VolumePopup-
// derived template as every other bar flyout.
PopupWindow {
    id: root

    property var anchorItem: null
    property var player: null

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: Theme.spacing.qsPanelWidth
    implicitHeight: content.implicitHeight + Theme.spacing.qsPanelPadY * 2

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: if (!hover.hovered)
            root.visible = false
    }
    // Position only advances via this Timer while the popup is open --
    // MprisPlayer.position isn't itself a ticking clock, it's a snapshot
    // that only changes on seek/track-change server-side, so a seek bar
    // bound directly to it would sit frozen between those events.
    property real displayPosition: root.player?.position ?? 0
    Timer {
        interval: 1000
        running: root.visible && (root.player?.isPlaying ?? false)
        repeat: true
        onTriggered: root.displayPosition = root.player?.position ?? 0
    }
    onPlayerChanged: root.displayPosition = root.player?.position ?? 0
    // Single onVisibleChanged handler -- QML doesn't allow declaring the
    // same signal handler twice on one object, so both the close-timer
    // reset and the position resync live in the one handler.
    onVisibleChanged: {
        if (visible) {
            closeTimer.stop();
            root.displayPosition = root.player?.position ?? 0;
        }
    }

    function fmtTime(seconds) {
        if (!seconds || seconds < 0)
            return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return `${m}:${s.toString().padStart(2, "0")}`;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.launcherBg
        border.color: Theme.color.launcherBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.panel

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.qsPanelPadX
            }
            topPadding: Theme.spacing.qsPanelPadY
            bottomPadding: Theme.spacing.qsPanelPadY
            spacing: Theme.spacing.qsSectionGap

            // Player picker -- only shown once a second player actually
            // exists, so the common single-player case stays uncluttered.
            Row {
                width: parent.width
                visible: Mpris.players.values.length > 1
                spacing: 6

                Repeater {
                    model: Mpris.players.values
                    delegate: Rectangle {
                        id: pickerDot
                        required property var modelData
                        width: 8
                        height: 8
                        radius: 4
                        color: pickerDot.modelData === root.player ? Theme.color.accentPurple : Theme.color.workspaceInactive
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.player = pickerDot.modelData }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacing.qsMediaGap

                Rectangle {
                    width: Theme.spacing.qsMediaArtSize * 1.5
                    height: Theme.spacing.qsMediaArtSize * 1.5
                    radius: Theme.radius.input
                    color: ThemeDefaults.alpha(Theme.base16.base03, 0.6)
                    Text {
                        anchors.centerIn: parent
                        text: "\u{F0387}" // md-music_note
                        renderType: Text.NativeRendering
                        font.family: Theme.font.family
                        font.pixelSize: Theme.spacing.qsMediaArtSize * 0.5
                        color: Theme.color.launcherPlaceholderFg
                    }
                }

                Column {
                    width: parent.width - Theme.spacing.qsMediaArtSize * 1.5 - Theme.spacing.qsMediaGap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: root.player?.trackTitle ?? "Nothing playing"
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeBase
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.player?.trackArtist ?? ""
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.player?.identity ?? ""
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: 9
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4
                visible: root.player?.positionSupported ?? false

                Item {
                    width: parent.width
                    height: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: Theme.radius.sliderTrack
                        color: Theme.color.workspaceInactive
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * ((root.player?.length ?? 0) > 0 ? Math.min(1, root.displayPosition / root.player.length) : 0)
                        height: 6
                        radius: Theme.radius.sliderTrack
                        color: Theme.color.accentPurple
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.player?.canSeek ?? false
                        function setFromX(x) {
                            if (root.player && root.player.length > 0)
                                root.player.position = Math.max(0, Math.min(1, x / width)) * root.player.length;
                        }
                        onPressed: mouse => setFromX(mouse.x)
                        onPositionChanged: mouse => {
                            if (pressed)
                                setFromX(mouse.x);
                        }
                    }
                }

                Row {
                    width: parent.width
                    Text {
                        width: parent.width / 2
                        text: root.fmtTime(root.displayPosition)
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: 9
                    }
                    Text {
                        width: parent.width / 2
                        horizontalAlignment: Text.AlignRight
                        text: root.fmtTime(root.player?.length ?? 0)
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: 9
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 20

                Text {
                    text: "\u{F04AE}" // md-skip_previous
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase + 2
                    color: (root.player?.canGoPrevious ?? false) ? Theme.color.fg : Theme.color.moduleDisabledFg
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.player?.previous() }
                }
                Text {
                    text: (root.player?.isPlaying ?? false) ? "\u{F03E4}" : "\u{F040A}" // md-pause / md-play
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase + 6
                    color: Theme.color.accentPurple
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.player?.togglePlaying() }
                }
                Text {
                    text: "\u{F04AD}" // md-skip_next
                    renderType: Text.NativeRendering
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase + 2
                    color: (root.player?.canGoNext ?? false) ? Theme.color.fg : Theme.color.moduleDisabledFg
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.player?.next() }
                }
            }
        }
    }
}
