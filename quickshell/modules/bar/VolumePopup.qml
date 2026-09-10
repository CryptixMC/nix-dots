import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../../theme"

// Click-to-open volume flyout (replaces launching pavucontrol directly on
// click) — drag the bar to set volume, click the mute glyph to toggle
// mute, click the "›" chevron to still open pavucontrol for anything this
// doesn't cover (per-app volume, output device switching, etc).
PopupWindow {
    id: root

    property var anchorItem: null
    property var sink: Pipewire.defaultAudioSink

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real volume: sink?.audio?.volume ?? 0

    visible: false
    grabFocus: false
    color: "transparent"

    implicitWidth: 220
    implicitHeight: content.implicitHeight + 20

    // Closes shortly after the pointer leaves the flyout — opening is an
    // explicit click on the icon, but closing shouldn't require one too.
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

    onVisibleChanged: if (visible)
        closeTimer.stop()

    Rectangle {
        anchors.fill: parent
        color: Colors.tooltipBg
        border.color: Colors.tooltipBorder
        border.width: 1
        radius: 6

        Row {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 10
                rightMargin: 10
            }
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.muted ? "󰝟" : "󰕾"
                color: Colors.accentPurple
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeBase
                renderType: Text.NativeRendering

                MouseArea {
                    anchors.fill: parent
                    onClicked: if (root.sink)
                        root.sink.audio.muted = !root.sink.audio.muted
                }
            }

            Item {
                id: sliderTrack
                width: 110
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Colors.workspaceInactive
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.min(1, root.volume)
                    height: 6
                    radius: 3
                    color: Colors.accentPurple
                }

                MouseArea {
                    anchors.fill: parent

                    function setFromX(x) {
                        if (!root.sink)
                            return;
                        root.sink.audio.volume = Math.max(0, Math.min(1, x / width));
                    }

                    onPressed: mouse => setFromX(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed)
                            setFromX(mouse.x);
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                text: `${Math.round(root.volume * 100)}%`
                color: Colors.tooltipFg
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeSmall
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: Colors.rightModuleFg
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeBase

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        Quickshell.execDetached(["sh", "-c", "pavucontrol"]);
                        root.visible = false;
                    }
                }
            }
        }
    }
}
