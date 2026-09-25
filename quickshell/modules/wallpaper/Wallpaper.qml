import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"

// One instance per screen (see shell.qml's Variants), rendering the active
// theme's declared wallpaper.engine ("static"/"gif"/"shader"/"scene") at
// the Background layer — supersedes hyprpaper (dropped from autostart,
// see hyprland.nix) since this now also covers static-only themes, not
// just gif/shader ones.
//
// A thin PanelWindow shell: the actual static/gif/shader/scene rendering
// lives in WallpaperContent.qml, shared with LockView.qml (a
// WlSessionLockSurface's contentItem, which has no layer-shell surface of
// its own to be a second Wallpaper PanelWindow). This file's own job is
// just the wlr-layer-shell plumbing and the per-monitor animation pause
// below, neither of which the lock screen needs or wants.
//
// Animation pauses per-monitor (not a single global flag) whenever that
// monitor's focused workspace has a fullscreen window, via
// Hyprland.monitorFor(screen) — confirmed against the installed qmltypes
// this session: monitorFor(QuickshellScreenInfo) -> HyprlandMonitor is a
// real method, and HyprlandMonitor.activeWorkspace.hasFullscreen is a real
// typed bool, not a lastIpcObject-guess like some other Hyprland state in
// this repo (Workspaces.qml/ActiveWindow.qml) had to fall back to.
PanelWindow {
    id: root

    // Variants (in shell.qml) injects each Quickshell.screens entry here —
    // the delegate root must declare this property itself for the model
    // value to land on it (same requirement as Bar.qml's identical
    // comment/property).
    property var modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // -1, not 0: on wlr-layer-shell, 0 means "reserve nothing for myself"
    // but still *respect* everyone else's exclusive zone, which made the
    // wallpaper start 26px down (0 26 1920 1174) — the bar's own reserved
    // strip — leaving bare compositor black behind the semi-transparent
    // bar. -1 is the protocol's "ignore other surfaces' exclusive zones
    // and give me the whole output", which is what a wallpaper wants.
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:wallpaper"
    color: "black"

    // wp.dir is baked in atomically alongside image/gif/shader by
    // ThemeDefaults.build() — deliberately not reconstructed here from
    // ThemeState.activeThemeName as a separate binding; that split was
    // observed to race on a live theme switch (this property settling to
    // the new theme before/after wp did, in either order), producing a
    // mismatched directory+filename pair.
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
