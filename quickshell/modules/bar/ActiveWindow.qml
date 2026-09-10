import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Mirrors waybar's "hyprland/window" module (format "{}", max-length 60).
// Shows the single globally-focused window title on every monitor for this
// pass — true per-output tracking (waybar's separate-outputs) is a
// follow-up refinement.
Item {
    id: root

    implicitWidth: label.implicitWidth + 14
    implicitHeight: 26

    // Hyprland.activeToplevel stays permanently null in this Quickshell
    // version (empirically confirmed: still null after
    // Hyprland.refreshToplevels() and several seconds of waiting) — derive
    // the focused window from the raw IPC data instead. focusHistoryID: 0
    // is Hyprland's own convention for "most recently focused" (the same
    // field `hyprctl clients -j` exposes), mirroring the
    // lastIpcObject.windows approach already used in Workspaces.qml.
    readonly property var activeToplevel: {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        return list.find(t => t.lastIpcObject?.focusHistoryID === 0) ?? null;
    }
    readonly property string rawTitle: activeToplevel?.title ?? ""
    readonly property string title: rawTitle.length > 60 ? rawTitle.slice(0, 60) + "…" : rawTitle

    Rectangle {
        width: 1
        color: Colors.windowSeparator
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            topMargin: 6
            bottomMargin: 6
        }
    }

    Text {
        id: label
        anchors {
            left: parent.left
            leftMargin: 7
            verticalCenter: parent.verticalCenter
        }
        text: root.title
        font.family: Colors.fontFamily
        font.pixelSize: Colors.fontSizeSmall
        renderType: Text.NativeRendering
        color: Colors.windowTitleFg
    }
}
