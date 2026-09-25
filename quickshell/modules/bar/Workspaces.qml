import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Workspace indicators: shows workspaces 1-5 plus any occupied workspace
// beyond that, focus-coloured when focused, dim when occupied-but-inactive,
// faint otherwise.
//
// Drawn as a Rectangle rather than a "●" text glyph. The glyph needed
// renderType: Text.NativeRendering to stop Qt substituting a bigger,
// coloured emoji "●" from a fallback font — a hazard a Rectangle doesn't
// have at all. Shape is token-driven so a theme can restyle it:
// radius.workspaceDot clamps to a circle by default and
// spacing.workspaceDotBorder at 0 keeps the solid fill, which is the v1
// dot; ultraviolet-v2 sets those to 1/1 for the design system's hollow
// square that fills only on focus.
//
// Root is an Item (not a bare Row) so it has a fixed implicitHeight matching
// the bar — without it, this block's height shrank to the dots' own font
// line height (~fontSizeWorkspace), leaving it top-aligned against its
// taller ActiveWindow sibling in Bar.qml's outer Row instead of vertically
// centered.
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
        // Per-dot label padding (0 3px each side), no separate
        // inter-button gap.
        spacing: Theme.spacing.workspaceDots

        Repeater {
            model: root.workspaceIds

            Rectangle {
                id: dot
                required property int modelData

                width: Theme.spacing.workspaceDotSize
                height: Theme.spacing.workspaceDotSize
                // Clamped, so the baseline's 999 reads as "circle" and v2's
                // 1 is taken literally.
                radius: Math.min(Theme.radius.workspaceDot, height / 2)

                readonly property var wsData: {
                    const list = Hyprland.workspaces ? Hyprland.workspaces.values : [];
                    return list.find(ws => ws.id === modelData) ?? null;
                }
                readonly property bool isFocused: Hyprland.focusedWorkspace?.id === modelData
                // "has windows" property unconfirmed against the installed
                // Quickshell version's HyprlandWorkspace type — lastIpcObject
                // mirrors `hyprctl workspaces -j`'s raw JSON (which has a
                // `windows` count field), used as the safest bet. Verify/
                // simplify if a direct property exists.
                readonly property bool isOccupied: (wsData?.lastIpcObject?.windows ?? 0) > 0

                readonly property color stateColor: isFocused ? Theme.color.workspaceFocused : (isOccupied ? Theme.color.workspaceOccupied : Theme.color.workspaceInactive)
                // Focused always fills — it's the one inverted indicator in
                // both themes. Everything else fills only when the theme
                // asks for solid dots (border 0); with a hairline border it
                // stays an outline, which is the v2 hollow square.
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
