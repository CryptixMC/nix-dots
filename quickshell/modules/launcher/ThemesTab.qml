import QtQuick
import "../../theme"

// Row 1 cycles installed themes (reuses ThemeLoader/ThemeState as-is — no
// new discovery mechanism). Row 2 shows the *active* theme's available
// wallpaper files (ThemeEntryLoader's wallpaper-file discovery) and lets
// you override which one renders (ThemeState.setWallpaperOverride) without
// touching the theme's own theme.json-declared default.
//
// No settings section: no theme.json currently declares any configurable
// options, so a generic toggle/dropdown-schema renderer would be untested
// speculative plumbing for zero real consumers — deferred until a theme
// actually wants to declare one (see TODO.md). "Renders nothing" for that
// case is satisfied here simply by not building it yet, matching the
// existing "colors-only theme has no settings" principle.
Column {
    id: root
    width: parent.width
    spacing: Theme.spacing.themeRowGap

    Row {
        spacing: Theme.spacing.themePillGap

        Repeater {
            model: ThemeLoader.discoveredThemeNames

            delegate: Rectangle {
                id: pill
                required property string modelData
                readonly property bool isActive: ThemeState.activeThemeName === modelData

                height: Theme.spacing.themePillHeight
                width: label.implicitWidth + Theme.spacing.themePillPadX * 2
                radius: height / 2
                color: isActive ? Theme.color.launcherItemSelectedBg : (pillMouse.containsMouse ? Theme.color.launcherInputBg : "transparent")
                border.width: Theme.spacing.borderHairline
                border.color: isActive ? Theme.color.accentPurple : (pillMouse.containsMouse ? Theme.color.accentPurple : Theme.color.launcherBorder)

                Behavior on color {
                    ColorAnimation { duration: Theme.motion.hoverColor.duration }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Theme.motion.hoverColor.duration }
                }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: pill.modelData
                    color: pill.isActive ? Theme.color.accentPurple : Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    font.capitalization: Font.Capitalize
                }

                MouseArea {
                    id: pillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ThemeState.setTheme(pill.modelData)
                }
            }
        }
    }

    Row {
        spacing: Theme.spacing.themeWallpaperGap
        visible: Theme.wallpaper.available.length > 0

        Repeater {
            model: Theme.wallpaper.available

            delegate: Rectangle {
                id: thumb
                required property string modelData
                // For "shader" engine, neither `image` nor `gif` is really
                // "the active" file (the shader composites its own image
                // field as a base texture, not a user-facing choice) —
                // only highlight for engines where one plain file is
                // unambiguously what's rendering.
                readonly property bool isActive: (Theme.wallpaper.engine === "static" && Theme.wallpaper.image === modelData) || (Theme.wallpaper.engine === "gif" && Theme.wallpaper.gif === modelData)

                width: Theme.spacing.themeWallpaperThumbWidth
                height: Theme.spacing.themeWallpaperThumbHeight
                radius: Theme.radius.input
                color: "transparent"
                border.width: isActive ? 2 : Theme.spacing.borderHairline
                border.color: isActive ? Theme.color.accentPurple : (thumbMouse.containsMouse ? Theme.color.purpleHover : Theme.color.launcherBorder)
                clip: true

                Behavior on border.color {
                    ColorAnimation { duration: Theme.motion.hoverColor.duration }
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    source: `file://${Theme.wallpaper.dir}/${thumb.modelData}`
                }

                MouseArea {
                    id: thumbMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ThemeState.setWallpaperOverride(ThemeState.activeThemeName, thumb.modelData)
                }
            }
        }
    }

    Text {
        visible: Theme.wallpaper.available.length === 0
        text: "This theme has no pickable wallpaper files."
        color: Theme.color.launcherPlaceholderFg
        font.family: Theme.font.family
        font.pixelSize: Theme.font.sizeSmall
    }
}
