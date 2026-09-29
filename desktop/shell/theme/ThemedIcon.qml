import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// Tints an icon toward the theme accent while keeping it recognizable.
// Explicit width/height on IconImage: implicitSize alone let fallback icons
// render oversized.
Item {
    id: root

    property alias source: icon.source
    property real iconSize: 24
    property bool themed: true

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    IconImage {
        id: icon
        width: root.iconSize
        height: root.iconSize
        anchors.centerIn: parent
        implicitSize: root.iconSize
        visible: !root.themed
    }

    MultiEffect {
        anchors.fill: icon
        source: icon
        visible: root.themed
        saturation: -0.25
        colorization: 0.3
        colorizationColor: Theme.color.accentPurple
    }
}
