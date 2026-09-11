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

    implicitWidth: Theme.spacing.volumePopupWidth
    implicitHeight: content.implicitHeight + Theme.spacing.volumePopupPadY

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
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        Row {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Theme.spacing.volumePopupInsetX
                rightMargin: Theme.spacing.volumePopupInsetX
            }
            spacing: Theme.spacing.volumePopupGap

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.muted ? "󰝟" : "󰕾"
                color: Theme.color.accentPurple
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase
                renderType: Text.NativeRendering

                MouseArea {
                    anchors.fill: parent
                    onClicked: if (root.sink)
                        root.sink.audio.muted = !root.sink.audio.muted
                }
            }

            Item {
                id: sliderTrack
                width: Theme.spacing.volumeSliderWidth
                height: Theme.spacing.volumeSliderHeight
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: Theme.radius.sliderTrack
                    color: Theme.color.workspaceInactive
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.min(1, root.volume)
                    height: 6
                    radius: Theme.radius.sliderTrack
                    color: Theme.color.accentPurple
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
                width: Theme.spacing.volumePercentLabelWidth
                text: `${Math.round(root.volume * 100)}%`
                color: Theme.color.tooltipFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: Theme.color.rightModuleFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeBase

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
