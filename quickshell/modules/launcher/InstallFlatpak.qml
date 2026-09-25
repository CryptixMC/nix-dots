import QtQuick
import Quickshell.Io
import "../../theme"

// Flatpak is entirely imperative and invisible to the flake -- flathub is
// already configured (modules/nixos/services/flatpak.nix) and several apps
// are already installed this way (Spotify, Whatsie, Parsec, ...), so this
// tab is a thin wrapper over `flatpak list`/`search`/`install`/`uninstall`
// via JobRunner, labelled as drift-outside-git rather than pretending it's
// declarative.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property var installed: []
    property var searchResults: []
    property string query: ""
    property bool searching: false

    function refreshInstalled() {
        listProc.running = true;
    }

    Component.onCompleted: root.refreshInstalled()

    Process {
        id: listProc
        command: ["flatpak", "list", "--app", "--columns=application,name,version"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                const apps = [];
                for (const raw of listOut.text.split("\n")) {
                    const line = raw.trim();
                    if (line.length === 0)
                        continue;
                    const cols = line.split("\t");
                    if (cols.length < 2)
                        continue;
                    apps.push({ id: cols[0], name: cols[1], version: cols[2] ?? "" });
                }
                apps.sort((a, b) => a.name.localeCompare(b.name));
                root.installed = apps;
            }
        }
    }

    Timer {
        id: debounce
        interval: 400
        onTriggered: {
            if (root.query.trim().length === 0) {
                root.searchResults = [];
                root.searching = false;
                return;
            }
            root.searching = true;
            searchProc.running = true;
        }
    }
    onQueryChanged: debounce.restart()

    Process {
        id: searchProc
        command: ["flatpak", "search", root.query, "--columns=application,name,description"]
        stdout: StdioCollector {
            id: searchOut
            onStreamFinished: {
                root.searching = false;
                const results = [];
                for (const raw of searchOut.text.split("\n")) {
                    const line = raw.trim();
                    if (line.length === 0 || line.startsWith("No matches found"))
                        continue;
                    const cols = line.split("\t");
                    if (cols.length < 2)
                        continue;
                    results.push({ id: cols[0], name: cols[1], description: cols[2] ?? "" });
                }
                root.searchResults = results;
            }
        }
    }

    property int _actionJobId: -1
    Connections {
        target: JobRunner
        function onJobsChanged() {
            if (root._actionJobId < 0)
                return;
            const job = JobRunner.jobById(root._actionJobId);
            if (!job || job.state === "running")
                return;
            root._actionJobId = -1;
            root.refreshInstalled();
        }
    }

    function install(appId) {
        root._actionJobId = JobRunner.run(`Install ${appId}`, ["flatpak", "install", "-y", "--user", "flathub", appId], { privileged: false });
    }
    function uninstall(appId) {
        root._actionJobId = JobRunner.run(`Uninstall ${appId}`, ["flatpak", "uninstall", "-y", appId], { privileged: false });
    }

    component ActionButton: Rectangle {
        id: btn
        required property string label
        signal activated
        width: label_.implicitWidth + 16
        height: 22
        radius: Theme.radius.input
        color: mouse.containsMouse ? Theme.color.launcherItemSelectedBg : "transparent"
        border.width: Theme.spacing.borderHairline
        border.color: Theme.color.launcherBorder

        Text {
            id: label_
            anchors.centerIn: parent
            text: btn.label
            color: Theme.color.fg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 16

        Column {
            width: parent.width
            spacing: 4

            Text {
                text: "Search Flathub"
                font.bold: true
                font.pixelSize: 13
                color: Theme.color.fg
                font.family: Theme.font.family
            }
            Rectangle {
                width: parent.width
                height: Theme.spacing.launcherInputHeight
                radius: Theme.radius.input
                color: Theme.color.launcherInputBg
                border.width: Theme.spacing.borderHairline
                border.color: Theme.color.launcherInputBorder

                TextInput {
                    anchors {
                        fill: parent
                        margins: Theme.spacing.launcherInputTextInset
                    }
                    color: Theme.color.fg
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.sizeBase
                    onTextChanged: root.query = text
                }
            }

            Text {
                visible: root.searching
                text: "searching…"
                color: Theme.color.launcherPlaceholderFg
                font.family: Theme.font.family
                font.pixelSize: Theme.font.sizeSmall
            }

            Repeater {
                model: root.searchResults

                delegate: Row {
                    required property var modelData
                    width: column.width
                    height: 24
                    spacing: 8

                    Text { width: 160; elide: Text.ElideRight; text: modelData.name; color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    Text { width: column.width - 160 - 70 - 16; elide: Text.ElideRight; text: modelData.description; color: Theme.color.launcherPlaceholderFg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    ActionButton { label: "install"; onActivated: root.install(modelData.id) }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 4

            Text {
                text: `Installed (${root.installed.length})  ·  user scope, outside git`
                font.bold: true
                font.pixelSize: 13
                color: Theme.color.fg
                font.family: Theme.font.family
            }

            Repeater {
                model: root.installed

                delegate: Row {
                    required property var modelData
                    width: column.width
                    height: 24
                    spacing: 8

                    Text { width: 200; elide: Text.ElideRight; text: modelData.name; color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    Text { width: column.width - 200 - 70 - 16; elide: Text.ElideRight; text: modelData.version; color: Theme.color.launcherPlaceholderFg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                    ActionButton { label: "remove"; onActivated: root.uninstall(modelData.id) }
                }
            }
        }
    }
}
