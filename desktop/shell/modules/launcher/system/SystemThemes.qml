import QtQuick
import "../../../theme"

// Theme cards showing each theme's palette (ThemeLoader.themes[name].base16),
// which says more about a theme than its wallpaper.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    readonly property var themeNames: ThemeLoader.discoveredThemeNames
    property int currentIndex: Math.max(0, root.themeNames.indexOf(ThemeState.activeThemeName))

    function moveLeft() {
        if (root.currentIndex <= 0)
            return false;
        root.currentIndex--;
        return true;
    }

    function moveRight() {
        if (root.currentIndex >= root.themeNames.length - 1)
            return false;
        root.currentIndex++;
        return true;
    }

    function activate() {
        const name = root.themeNames[root.currentIndex];
        if (name)
            ThemeState.setTheme(name);
    }

    // Keyboard cycling applies the theme immediately, like SUPER+T.
    onCurrentIndexChanged: root.activate()

    readonly property var accentKeys: ["base08", "base09", "base0A", "base0B", "base0C", "base0D", "base0E", "base0F"]

    Column {
        id: column
        width: parent.width
        spacing: Theme.spacing.themeRowGap

        Text {
            text: "Themes"
            font.bold: true
            font.pixelSize: 16
            color: Theme.color.fg
        }

        Flow {
            width: parent.width
            spacing: Theme.spacing.themeWallpaperGap

            Repeater {
                model: root.themeNames

                delegate: Rectangle {
                    id: card
                    required property string modelData
                    required property int index
                    readonly property var themeData: ThemeLoader.themes[modelData]
                    readonly property bool isActive: ThemeState.activeThemeName === modelData
                    readonly property bool isCurrent: index === root.currentIndex

                    width: Theme.spacing.themeWallpaperThumbWidth
                    height: Theme.spacing.themeWallpaperThumbHeight + 22
                    radius: Theme.radius.input
                    color: "transparent"

                    Rectangle {
                        id: band
                        width: parent.width
                        height: Theme.spacing.themeWallpaperThumbHeight
                        radius: Theme.radius.input
                        color: card.themeData ? ThemeDefaults.opaque(card.themeData.base16.base01) : Theme.color.launcherInputBg
                        border.width: card.isActive ? 2 : (card.isCurrent ? Theme.spacing.borderHairline + 1 : Theme.spacing.borderHairline)
                        border.color: card.isActive ? Theme.color.accentPurple : (cardMouse.containsMouse || card.isCurrent ? Theme.color.purpleHover : Theme.color.launcherBorder)
                        clip: true

                        Behavior on border.color {
                            ColorAnimation { duration: Theme.motion.hoverColor.duration }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "◆"
                                renderType: Text.NativeRendering
                                font.pixelSize: 26
                                color: card.themeData ? ThemeDefaults.opaque(card.themeData.base16.base0C) : Theme.color.accentPurple
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 3

                                Repeater {
                                    model: root.accentKeys

                                    delegate: Rectangle {
                                        required property string modelData
                                        width: 10
                                        height: 10
                                        radius: 2
                                        color: card.themeData ? ThemeDefaults.opaque(card.themeData.base16[modelData]) : "transparent"
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors {
                            top: band.bottom
                            left: parent.left
                            right: parent.right
                            topMargin: 4
                        }
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData
                        color: card.isActive ? Theme.color.accentPurple : Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        font.capitalization: Font.Capitalize
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.currentIndex = card.index;
                            ThemeState.setTheme(card.modelData);
                        }
                    }
                }
            }
        }

        // Slight-transparency toggle for menu surfaces. Theming controls belong
        // here, not in a separate launcher tab.
        Rectangle {
            width: 220
            height: Theme.spacing.launcherTabHeight - 6
            radius: Theme.radius.input
            color: ThemeState.menuTranslucent ? Theme.color.launcherItemSelectedBg : "transparent"
            border.width: Theme.spacing.borderHairline
            border.color: ThemeState.menuTranslucent ? Theme.color.launcherInputBorder : Theme.color.launcherBorder

            Text {
                anchors.centerIn: parent
                text: ThemeState.menuTranslucent ? "✓ slight transparency" : "slight transparency"
                color: Theme.color.fg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: ThemeState.setMenuTranslucent(!ThemeState.menuTranslucent)
            }
        }

        // Wallpaper picker: universal live scenes (wallpaper/scenes/registry.js)
        // first, then this theme's file wallpapers. Both use
        // ThemeState.setWallpaperOverride(); scenes render as labeled cards.
        Text {
            text: "Wallpaper"
            font.bold: true
            font.pixelSize: 14
            color: Theme.color.fg
            visible: Theme.availableScenes.length > 0 || Theme.wallpaper.available.length > 0
        }

        Flow {
            width: parent.width
            spacing: Theme.spacing.themeWallpaperGap
            visible: Theme.availableScenes.length > 0 || Theme.wallpaper.available.length > 0

            Repeater {
                model: Theme.availableScenes

                delegate: Rectangle {
                    id: sceneCard
                    required property var modelData
                    readonly property bool isActive: Theme.wallpaper.engine === "scene" && Theme.wallpaper.scene === sceneCard.modelData.name

                    width: Theme.spacing.themeWallpaperThumbWidth
                    height: Theme.spacing.themeWallpaperThumbHeight
                    radius: Theme.radius.input
                    color: Theme.color.groundApp
                    border.width: isActive ? 2 : Theme.spacing.borderHairline
                    border.color: isActive ? Theme.color.accentPurple : (sceneCardMouse.containsMouse ? Theme.color.purpleHover : Theme.color.launcherBorder)
                    clip: true

                    Behavior on border.color {
                        ColorAnimation { duration: Theme.motion.hoverColor.duration }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: sceneCard.modelData.label
                        color: Theme.color.accentPurple
                        font.bold: true
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: sceneCardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ThemeState.setWallpaperOverride(ThemeState.activeThemeName, sceneCard.modelData.name)
                    }
                }
            }

            Repeater {
                model: Theme.wallpaper.available

                delegate: Rectangle {
                    id: wthumb
                    required property string modelData
                    readonly property bool isActive: (Theme.wallpaper.engine === "static" && Theme.wallpaper.image === modelData) || (Theme.wallpaper.engine === "gif" && Theme.wallpaper.gif === modelData)

                    width: Theme.spacing.themeWallpaperThumbWidth
                    height: Theme.spacing.themeWallpaperThumbHeight
                    radius: Theme.radius.input
                    color: "transparent"
                    border.width: isActive ? 2 : Theme.spacing.borderHairline
                    border.color: isActive ? Theme.color.accentPurple : (wthumbMouse.containsMouse ? Theme.color.purpleHover : Theme.color.launcherBorder)
                    clip: true

                    Behavior on border.color {
                        ColorAnimation { duration: Theme.motion.hoverColor.duration }
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: parent.border.width
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        source: `file://${Theme.wallpaper.dir}/${wthumb.modelData}`
                    }

                    MouseArea {
                        id: wthumbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ThemeState.setWallpaperOverride(ThemeState.activeThemeName, wthumb.modelData)
                    }
                }
            }
        }
    }
}
