import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// Tints a real icon toward the active theme's accent color — similar in
// spirit to macOS's adaptive icon tinting: a partial desaturation plus a
// colorization blend, so real app/file icons read as "themed" without
// losing enough of their own shape/contrast to become unrecognizable.
// Retints automatically on a live theme switch since Theme.color.accentPurple
// is itself reactive.
//
// Explicit width/height (not just implicitSize) on the inner IconImage —
// relying on implicitSize alone let a failed-lookup fallback icon render
// at some other, larger native size instead of the requested one,
// confirmed live in the Files tab grid (oversized fallback glyphs).
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
