import QtQuick
import "../../../theme"

// Data-driven right-click menu ({label, glyph, enabled, danger, submenu, action}).
// A plain overlay Item, not a PopupWindow: a stray layer-shell surface can eat
// keyboard input. Submenus drill in with a "Back" row instead of flyouts.
// Position is clamped inside FilesTab, since the tab's Loader clips anything outside it.
Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 500

    readonly property real rowHeight: 28
    readonly property real menuWidth: 220

    property var stack: []
    property real requestedX: 0
    property real requestedY: 0

    signal closed

    function openAt(x, y, rootItems) {
        root.stack = [
            {
                title: "",
                items: rootItems
            }
        ];
        root.requestedX = x;
        root.requestedY = y;
        root.visible = true;
    }

    function close() {
        root.visible = false;
        root.stack = [];
        root.closed();
    }

    readonly property var level: root.stack.length > 0 ? root.stack[root.stack.length - 1] : {
        title: "",
        items: []
    }
    readonly property bool hasBack: root.stack.length > 1
    readonly property int rowCount: root.level.items.length + (root.hasBack ? 1 : 0)
    readonly property real menuHeight: root.rowCount * root.rowHeight + 8

    readonly property real posX: Math.max(4, Math.min(root.requestedX, root.width - root.menuWidth - 4))
    readonly property real posY: (root.requestedY + root.menuHeight <= root.height) ? root.requestedY : Math.max(4, root.requestedY - root.menuHeight)

    function activateItem(item) {
        if (!item || item.enabled === false)
            return;
        if (item.submenu) {
            root.stack = root.stack.concat([
                {
                    title: item.label,
                    items: item.submenu
                }
            ]);
            return;
        }
        if (item.action)
            item.action();
        // `keepOpen` is for actions that build their submenu asynchronously (Open With
        // pushes a "Loading…" level and replaces it), so closing here would tear it down.
        if (!item.keepOpen)
            root.close();
    }

    function back() {
        if (root.stack.length > 1)
            root.stack = root.stack.slice(0, -1);
        else
            root.close();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.close()
    }

    Rectangle {
        x: root.posX
        y: root.posY
        width: root.menuWidth
        height: root.menuHeight
        radius: Theme.radius.popup
        color: Theme.color.launcherBg
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        MouseArea {
            anchors.fill: parent
            // Swallows clicks so they don't reach the backdrop's close handler.
        }

        Column {
            anchors {
                fill: parent
                margins: 4
            }

            Rectangle {
                width: parent.width
                height: root.rowHeight
                visible: root.hasBack
                radius: Theme.radius.input
                color: backMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6
                    Text {
                        text: "←"
                        color: Theme.color.launcherPlaceholderFg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                    }
                    Text {
                        text: root.level.title
                        color: Theme.color.fg
                        font.family: Theme.font.family
                        font.pixelSize: Theme.font.sizeSmall
                        font.bold: true
                    }
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.back()
                }
            }

            Repeater {
                model: root.level.items

                delegate: Item {
                    id: itemRoot
                    required property var modelData
                    required property int index
                    readonly property bool isSeparator: modelData.separator === true

                    width: parent.width
                    height: isSeparator ? 9 : root.rowHeight

                    Rectangle {
                        visible: itemRoot.isSeparator
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4
                            rightMargin: 4
                        }
                        height: Theme.spacing.borderHairline
                        color: Theme.color.launcherBorder
                    }

                    Rectangle {
                        visible: !itemRoot.isSeparator
                        anchors.fill: parent
                        radius: Theme.radius.input
                        color: (rowMouse.containsMouse && itemRoot.modelData.enabled !== false) ? Theme.color.launcherItemSelectedBg : "transparent"

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: 8
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 6

                            Text {
                                width: 16
                                text: itemRoot.modelData.glyph ?? ""
                                color: itemRoot.modelData.danger ? Theme.color.accentPink : Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                                renderType: Text.NativeRendering
                            }

                            Text {
                                width: parent.width - 16 - (itemRoot.modelData.submenu ? 16 : 0) - 6
                                text: itemRoot.modelData.label
                                elide: Text.ElideRight
                                color: itemRoot.modelData.enabled === false ? Theme.color.moduleDisabledFg : (itemRoot.modelData.danger ? Theme.color.accentPink : Theme.color.fg)
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }

                            Text {
                                visible: !!itemRoot.modelData.submenu
                                text: "›"
                                color: Theme.color.launcherPlaceholderFg
                                font.family: Theme.font.family
                                font.pixelSize: Theme.font.sizeSmall
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: itemRoot.modelData.enabled !== false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateItem(itemRoot.modelData)
                        }
                    }
                }
            }
        }
    }
}
