import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme"

// Trimmed re-implementation of quickshell/modules/wallpaper/Wallpaper.qml
// for the greeter — static+gif only (no qsb-shader/scene machinery; not
// worth the build complexity for a login screen), and no per-monitor
// fullscreen-pause logic since cage is a single-app kiosk compositor with
// no concept of a user-managed fullscreen window pre-login.
//
// Prefers a LIVE snapshot of the desktop session's actual current
// wallpaper over the bundled static fallback below. The desktop session
// (Theme.qml's syncGreeterWallpaper()) writes that snapshot -- one image
// plus a JSON sidecar naming it -- to /var/lib/quickshell-greeter/ on every
// theme or wallpaper change; this file is the read side. See greetd.nix's
// systemd.tmpfiles.rules for why that directory (not $HOME, which is 0700)
// is where the handoff happens.
Item {
    id: root
    anchors.fill: parent

    readonly property string shareDir: "/var/lib/quickshell-greeter"
    // null until sharedMetaFile loads successfully -- which never happens
    // on a fresh install that's booted straight to the greeter without
    // cryptix ever logging in once to run the sync, so `useShared` below
    // has to degrade cleanly rather than assume this is always populated.
    property var sharedMeta: null

    FileView {
        id: sharedMetaFile
        path: `${root.shareDir}/wallpaper.json`
        // Live, not one-shot: this file is genuinely long-running relative
        // to how often the desktop session might change its wallpaper, and
        // re-reading a JSON sidecar on change is cheap.
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
    // Bundled fallback dir/file (theme/wallpapers/, Colors.wallpaperFile) --
    // exactly what this file did unconditionally before the shared snapshot
    // existed, now demoted to "what a fresh install shows before the first
    // sync ever runs."
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
