import QtQuick
// Static import purely so Quickshell's qmlscanner registers every type in
// scenes/ up front — see Wallpaper.qml's identical comment on the same
// import for why this has to be eager, not the Loader's lazy runtime lookup.
import "scenes"

// The actual static/gif/shader/scene rendering — split out of Wallpaper.qml
// (which stays a PanelWindow at the Background layer, wlr-layer-shell only)
// so a second surface with no layer-shell of its own can show the exact
// same live wallpaper. LockView.qml is that second surface: a
// WlSessionLockSurface's contentItem, which needs the identical render
// logic embedded directly rather than composited from a separate
// PanelWindow surface.
//
// Takes wp/shouldAnimate as required properties instead of deriving them
// itself (Theme.wallpaper, Hyprland.monitorFor(screen)) -- the two current
// callers resolve "should this be animating right now" differently
// (Wallpaper.qml pauses per-monitor on a fullscreen window; LockView has no
// equivalent concept and just always animates), and this file has no
// business knowing which.
Item {
    id: root

    required property var wp
    required property bool shouldAnimate
    // Defaults true (every existing caller's behaviour, unchanged) --
    // LockView.qml sets this false so its own left-column content doesn't
    // collide with a scene's system-stats HUD occupying the same corner.
    // See Orbital.qml's showHud for the actual gate.
    property bool showSceneHud: true

    readonly property var sceneComponents: ({ "Orbital": orbitalComponent, "NeuralNet": neuralNetComponent })
    readonly property Component sceneComponent: root.sceneComponents[root.wp.scene ?? ""] ?? null
    readonly property bool sceneActive: root.wp.engine === "scene" && root.sceneComponent !== null

    Image {
        id: baseImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: root.wp.engine !== "gif" && !root.sceneActive
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
    // pays nothing for it -- see Wallpaper.qml's original comment (still
    // accurate) on why the ShaderEffect itself must stay gated too.
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

    // A Component (not a Loader.source URL string) so `shouldAnimate` -- a
    // required property on Orbital.qml -- is satisfied declaratively; see
    // Wallpaper.qml's original comment for the "logs an error otherwise"
    // reasoning, still accurate here.
    Component {
        id: orbitalComponent
        Orbital {
            shouldAnimate: root.shouldAnimate
            showHud: root.showSceneHud
        }
    }

    Component {
        id: neuralNetComponent
        NeuralNet {
            shouldAnimate: root.shouldAnimate
            showHud: root.showSceneHud
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sceneActive
        visible: active
        asynchronous: true
        sourceComponent: root.sceneComponent
    }
}
