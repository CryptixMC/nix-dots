import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Workspace indicators: 1-5 plus any occupied workspace beyond that.
//
// Drawn as a Rectangle, not a "●" glyph, which Qt could substitute with a
// coloured emoji from a fallback font. Shape is token-driven:
// radius.workspaceDot and spacing.workspaceDotBorder let a theme switch
// between solid circles and hollow squares.
//
// Root is an Item with the bar's height so it centers vertically next to
// ActiveWindow in Bar.qml's Row.
Item {
    id: root

    implicitWidth: dotsRow.implicitWidth
    implicitHeight: Theme.spacing.barHeight

    readonly property var workspaceIds: {
        const ids = {};
        for (let i = 1; i <= 5; i++)
            ids[i] = true;
        const list = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        for (const ws of list)
            ids[ws.id] = true;
        return Object.keys(ids).map(Number).sort((a, b) => a - b);
    }

    Row {
        id: dotsRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.workspaceDots

        Repeater {
            model: root.workspaceIds

            Rectangle {
                id: dot
                required property int modelData

                width: Theme.spacing.workspaceDotSize
                height: Theme.spacing.workspaceDotSize
                // Clamped so a large radius means "circle".
                radius: Math.min(Theme.radius.workspaceDot, height / 2)

                readonly property var wsData: {
                    const list = Hyprland.workspaces ? Hyprland.workspaces.values : [];
                    return list.find(ws => ws.id === modelData) ?? null;
                }
                readonly property bool isFocused: Hyprland.focusedWorkspace?.id === modelData
                // lastIpcObject mirrors `hyprctl workspaces -j`, which has a
                // `windows` count.
                readonly property bool isOccupied: (wsData?.lastIpcObject?.windows ?? 0) > 0

                readonly property color stateColor: isFocused ? Theme.color.workspaceFocused : (isOccupied ? Theme.color.workspaceOccupied : Theme.color.workspaceInactive)
                // Focused always fills; others fill only when the theme
                // uses solid dots (border 0).
                readonly property bool filled: isFocused || Theme.spacing.workspaceDotBorder === 0

                color: filled ? stateColor : "transparent"
                border.width: Theme.spacing.workspaceDotBorder
                border.color: stateColor

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.motion.hoverColor.duration
                        easing.type: Theme.motion.hoverColor.easing
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("workspace " + dot.modelData)
                }
            }
        }
    }
}
