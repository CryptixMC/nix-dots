import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Mirrors waybar's "hyprland/window" module (format "{}", max-length 60).
// Shows the single globally-focused window title on every monitor for this
// pass — true per-output tracking (waybar's separate-outputs) is a
// follow-up refinement.
Item {
    id: root

    implicitWidth: label.implicitWidth + Theme.spacing.activeWindowPad
    implicitHeight: Theme.spacing.barHeight

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
