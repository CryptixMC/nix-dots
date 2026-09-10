import QtQuick
import Quickshell.Hyprland
import "../../theme"

// Workspace dots, mirrors waybar's "hyprland/workspaces" module:
// persistent-workspaces."*" = 5 plus any occupied workspace beyond that,
// pink when focused, dim when occupied-but-inactive, faint otherwise.
//
// Root is an Item (not a bare Row) so it has a fixed implicitHeight matching
// the bar — without it, this block's height shrank to the dots' own font
// line height (~fontSizeWorkspace), leaving it top-aligned against its
// taller ActiveWindow sibling in Bar.qml's outer Row instead of vertically
// centered.
Item {
    id: root

    implicitWidth: dotsRow.implicitWidth
    implicitHeight: Colors.barHeight

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
        // Approximates waybar's per-dot label padding (0 3px each side, no
        // separate inter-button gap in the CSS).
        spacing: 6

        Repeater {
            model: root.workspaceIds

            Text {
                required property int modelData

                text: "●"
                font.family: Colors.fontFamily
                font.pixelSize: Colors.fontSizeWorkspace
                // Without this, Qt substituted a color-emoji "●" fallback
                // glyph (bigger and colored) instead of the plain dot from
                // this font — same root cause as the right-side icon blobs.
                renderType: Text.NativeRendering

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

                color: isFocused ? Colors.accentPink : (isOccupied ? Colors.workspaceOccupied : Colors.workspaceInactive)

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("workspace " + modelData)
                }
            }
        }
    }
}
