import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Active-window title, truncated to 60 chars. Shows the globally focused
// window on every monitor; per-output tracking is not implemented.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.spacing.activeWindowPad
    implicitHeight: Theme.spacing.barHeight

    // Hyprland.activeToplevel stays null in this Quickshell version, so
    // derive focus from IPC data: focusHistoryID 0 is the most recent.
    readonly property var activeToplevel: {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        return list.find(t => t.lastIpcObject?.focusHistoryID === 0) ?? null;
    }
    readonly property string rawTitle: activeToplevel?.title ?? ""
    readonly property string title: rawTitle.length > 60 ? rawTitle.slice(0, 60) + "…" : rawTitle

    Rectangle {
        width: Theme.spacing.borderHairline
        color: Theme.color.windowSeparator
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            topMargin: Theme.spacing.separatorInset
            bottomMargin: Theme.spacing.separatorInset
        }
    }

    Text {
        id: label
        anchors {
            left: parent.left
            leftMargin: Theme.spacing.activeWindowLabelInset
            verticalCenter: parent.verticalCenter
        }
        text: root.title
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
        renderType: Text.NativeRendering
        color: Theme.color.windowTitleFg
    }
}
