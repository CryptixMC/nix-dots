import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../theme"

// One instance per screen (see shell.qml's Variants), rendering the active
// theme's declared wallpaper.engine ("static"/"gif"/"shader") at the
// Background layer — supersedes hyprpaper (dropped from autostart, see
// hyprland.nix) since this now also covers static-only themes, not just
// gif/shader ones.
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

    Image {
        id: baseImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: root.wp.engine !== "gif"
        source: (root.wp.engine === "static" || root.wp.engine === "shader") ? `file://${root.wp.dir}/${root.wp.image}` : ""
        asynchronous: true
    }

    AnimatedImage {
        id: gifImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: root.wp.engine === "gif"
        source: visible ? `file://${root.wp.dir}/${root.wp.gif}` : ""
        playing: visible && root.shouldAnimate
        cache: true
    }

    // The whole shader pipeline lives behind a Loader so a static/gif theme
    // pays nothing for it. Previously ShaderEffectSource sat here
    // unconditionally with `live: true` (ungated, unlike its sibling
    // hideSource/visible bindings), which kept a full-screen RGBA FBO
    // allocated per monitor on every theme, and the always-present
    // ShaderEffect with an empty fragmentShader fell back to Qt's default
    // shader — which samples a uniform named `source` this element doesn't
    // declare, logging "ShaderEffect: 'source' does not have a matching
    // property" on every reload.
    Loader {
        anchors.fill: parent
        active: root.wp.engine === "shader"
        visible: active

        sourceComponent: Item {
            ShaderEffectSource {
                id: shaderSource
                sourceItem: baseImage
                hideSource: true
                live: true
                visible: false
            }

            ShaderEffect {
                id: shaderOverlay
                anchors.fill: parent

                property variant baseSource: shaderSource
                property real time: 0
                property vector3d colorMauve: Qt.vector3d(0xcb / 255, 0xa6 / 255, 0xf7 / 255)
                property vector3d colorLavender: Qt.vector3d(0xb4 / 255, 0xbe / 255, 0xfe / 255)
                property vector3d colorBlue: Qt.vector3d(0x89 / 255, 0xb4 / 255, 0xfa / 255)
                property real intensity: 1.3

                fragmentShader: `file://${root.wp.dir}/${root.wp.shader}.qsb`

                Timer {
                    interval: 16
                    running: root.shouldAnimate
                    repeat: true
                    onTriggered: shaderOverlay.time += interval / 1000
                }
            }
        }
    }
}
