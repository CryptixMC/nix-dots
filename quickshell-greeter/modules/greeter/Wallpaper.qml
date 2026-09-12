import QtQuick
import Quickshell
import "../../theme"

// Trimmed re-implementation of quickshell/modules/wallpaper/Wallpaper.qml
// for the greeter — static+gif only (no qsb-shader machinery; not worth the
// build complexity for a login screen), and no per-monitor
// fullscreen-pause logic since cage is a single-app kiosk compositor with
// no concept of a user-managed fullscreen window pre-login. Not driven by
// the main shell's theme registry — theme/Colors.qml's own decoupling
// rationale applies here too.
Item {
    id: root
    anchors.fill: parent

    readonly property string wallpaperDir: `${Quickshell.shellDir}/theme/wallpapers`
    readonly property bool isGif: Colors.wallpaperFile.toLowerCase().endsWith(".gif")

    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: !root.isGif
        source: !root.isGif ? `file://${root.wallpaperDir}/${Colors.wallpaperFile}` : ""
        asynchronous: true
    }

    AnimatedImage {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: root.isGif
        source: root.isGif ? `file://${root.wallpaperDir}/${Colors.wallpaperFile}` : ""
        playing: visible
        cache: true
    }
}
