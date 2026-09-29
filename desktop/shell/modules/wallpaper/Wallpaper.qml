import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"

// One per screen: renders the active theme's wallpaper at the Background layer.
// Rendering lives in WallpaperContent.qml (shared with LockView.qml); this file
// only does layer-shell plumbing and pauses animation while the monitor has a fullscreen window.
PanelWindow {
    id: root

    // Variants injects each screen here; the delegate root must declare this property.
    property var modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // -1 ignores other surfaces' exclusive zones (e.g. the bar); 0 would still respect them
    // and leave a black strip behind the translucent bar.
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:wallpaper"
    color: "black"

    // wp.dir is set atomically with the filenames; deriving it separately from the
    // theme name races on theme switch and mismatches directory and file.
    readonly property var wp: Theme.wallpaper
    readonly property var monitor: Hyprland.monitorFor(root.screen)
    readonly property bool fullscreenActive: root.monitor?.activeWorkspace?.hasFullscreen ?? false
    readonly property bool shouldAnimate: !root.fullscreenActive

    WallpaperContent {
        anchors.fill: parent
        wp: root.wp
        shouldAnimate: root.shouldAnimate
    }
}
