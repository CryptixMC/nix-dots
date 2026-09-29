import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"

// Static/gif-only wallpaper. Prefers the desktop session's live snapshot in
// /var/lib/quickshell-greeter/ (written by Theme.qml's syncGreeterWallpaper();
// $HOME is 0700, see greetd.nix tmpfiles) over the bundled fallback.
Item {
    id: root
    anchors.fill: parent

    readonly property string shareDir: "/var/lib/quickshell-greeter"
    // Null until the snapshot exists (e.g. fresh install, no login yet).
    property var sharedMeta: null

    FileView {
        id: sharedMetaFile
        path: `${root.shareDir}/wallpaper.json`
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                root.sharedMeta = JSON.parse(text());
            } catch (e) {
                root.sharedMeta = null;
            }
        }
        onLoadFailed: root.sharedMeta = null
    }

    readonly property bool useShared: root.sharedMeta !== null && root.sharedMeta.file
    // Bundled fallback, used until the desktop session has synced a snapshot.
    readonly property string wallpaperDir: root.useShared ? root.shareDir : `${Quickshell.shellDir}/theme/wallpapers`
    readonly property string wallpaperFile: root.useShared ? root.sharedMeta.file : Colors.wallpaperFile
    readonly property bool isGif: root.useShared ? (root.sharedMeta.isGif ?? false) : Colors.wallpaperFile.toLowerCase().endsWith(".gif")

    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: !root.isGif
        source: !root.isGif ? `file://${root.wallpaperDir}/${root.wallpaperFile}` : ""
        asynchronous: true
    }

    AnimatedImage {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: root.isGif
        source: root.isGif ? `file://${root.wallpaperDir}/${root.wallpaperFile}` : ""
        playing: visible
        cache: true
    }
}
