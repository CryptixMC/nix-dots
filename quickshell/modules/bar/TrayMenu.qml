import QtQuick
import Quickshell
import "../../theme"

// Custom-drawn DBusMenu popup for Tray.qml's right-click context menu.
// SystemTrayItem/QsMenuEntry both expose a `display()` that opens a native
// QPlatformMenu, but that path only works when quickshell is started with
// `pragma UseQApplication` -- this shell isn't (see shell.qml), so display()
// silently no-ops with a logged "not started in QApplication mode" error
// and no menu ever appeared, which is the actual bug this file fixes.
// QsMenuOpener sidesteps display() entirely by walking the DBusMenu tree
// ourselves and drawing it as an ordinary themed popup -- same
// PopupWindow/HoverHandler-driven-close architecture as every other bar
// popup (QuickSettingsPanel.qml's header comment: "no new popup
// architecture invented").
PopupWindow {
    id: root

    property var anchorItem: null
    property var menuHandle: null
    // Drill-down stack for hasChildren entries: each pushed value is the
    // parent QsMenuEntry whose children should render next. Empty stack
    // means "showing the root menu" -- QsMenuEntry is itself a
    // QsMenuHandle, so re-targeting `opener.menu` to it is the same move
    // as targeting the tray item's own top-level menu handle.
    property var stack: []

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.adjustment: PopupAdjustment.Slide

    visible: false
    grabFocus: false
    color: "transparent"

    onVisibleChanged: {
        if (visible)
            closeTimer.stop();
        else
            root.stack = [];
    }

    QsMenuOpener {
        id: opener
        menu: root.stack.length > 0 ? root.stack[root.stack.length - 1] : root.menuHandle
    }

    implicitWidth: Theme.spacing.trayMenuWidth
    implicitHeight: content.implicitHeight + Theme.spacing.launcherContentInset * 2

    HoverHandler {
        id: hover
        onHoveredChanged: if (!hovered)
            closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: 800
        onTriggered: if (!hover.hovered)
            root.visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.tooltipBg
        border.color: Theme.color.tooltipBorder
        border.width: Theme.spacing.borderHairline
        radius: Theme.radius.popup

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Theme.spacing.launcherContentInset
            }

            Rectangle {
                visible: root.stack.length > 0
                width: parent.width
                height: Theme.spacing.launcherRowHeight
                radius: Theme.radius.input
                color: backMouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.spacing.launcherRowInset
                        verticalCenter: parent.verticalCenter
                    }
                    text: "‹ Back"
                    color: Theme.color.rightModuleFg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stack = root.stack.slice(0, -1)
                }
            }

            Text {
                visible: opener.children.values.length === 0
                text: "(empty)"
                color: Theme.color.tooltipMuted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: row
                    required property var modelData

                    width: content.width
                    height: row.modelData.isSeparator ? Theme.spacing.borderHairline + Theme.spacing.launcherContentGap : Theme.spacing.launcherRowHeight

                    Rectangle {
                        visible: row.modelData.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: Theme.spacing.borderHairline
                        color: Theme.color.tooltipBorder
                    }

                    Rectangle {
                        visible: !row.modelData.isSeparator
                        anchors.fill: parent
                        radius: Theme.radius.input
                        color: itemMouse.containsMouse && row.modelData.enabled ? Theme.color.launcherItemSelectedBg : "transparent"

                        Text {
                            anchors {
                                left: parent.left
                                right: chevron.left
                                leftMargin: Theme.spacing.launcherRowInset
                                rightMargin: Theme.spacing.launcherRowInset
                                verticalCenter: parent.verticalCenter
                            }
                            elide: Text.ElideRight
                            text: (row.modelData.buttonType !== QsMenuButtonType.None && row.modelData.checkState === Qt.Checked ? "✓ " : "") + row.modelData.text
                            color: row.modelData.enabled ? Theme.color.fg : Theme.color.moduleDisabledFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                        }

                        Text {
                            id: chevron
                            visible: row.modelData.hasChildren
                            anchors {
                                right: parent.right
                                rightMargin: Theme.spacing.launcherRowInset
                                verticalCenter: parent.verticalCenter
                            }
                            width: visible ? implicitWidth : 0
                            text: "›"
                            color: Theme.color.rightModuleFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeBase
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: row.modelData.enabled
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.modelData.hasChildren)
                                    root.stack = root.stack.concat([row.modelData]);
                                else {
                                    row.modelData.triggered();
                                    root.visible = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
