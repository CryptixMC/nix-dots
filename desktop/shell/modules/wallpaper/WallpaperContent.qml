import QtQuick
// Static import so qmlscanner registers every scene type eagerly.
import "scenes"

// Wallpaper rendering (static/gif/shader/scene), shared by Wallpaper.qml and LockView.qml.
// wp/shouldAnimate are passed in because each caller decides pausing differently.
Item {
    id: root

    required property var wp
    required property bool shouldAnimate
    // LockView sets this false so a scene's HUD doesn't collide with its own content.
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

    // Behind a Loader so static/gif themes pay nothing for the shader pipeline.
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

    // A Component (not a Loader.source URL) so the required shouldAnimate is set declaratively.
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
