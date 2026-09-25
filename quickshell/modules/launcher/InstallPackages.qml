import QtQuick
import Quickshell.Io
import "../../theme"

// Live `nix search` (debounced), not a pre-built offline index -- the
// index-build path the original plan sketched (minutes, ~50MB via
// JobRunner, cached to disk, invalidated on flake.lock drift) is real
// future work, not implemented this pass. This is deliberately the same
// "live fallback" path that design always kept as the never-dead-on-a-
// missing-index case, just promoted to the only path for now: still a
// genuinely usable search, just ~1-2s per query instead of instant.
//
// searchQuery comes from the outer launcher search box (SystemTab threads
// it down, same convention Files/Games use) rather than a second, separate
// TextInput here.
Item {
    id: root
    width: parent.width
    implicitHeight: column.implicitHeight

    property string searchQuery: ""
    property var results: []
    property bool searching: false
    property string errorText: ""

    Timer {
        id: debounce
        interval: 500
        onTriggered: {
            const q = root.searchQuery.trim();
            if (q.length === 0) {
                root.results = [];
                root.searching = false;
                root.errorText = "";
                return;
            }
            root.searching = true;
            root.errorText = "";
            searchProc.command = ["nix", "search", "nixpkgs", q, "--json"];
            searchProc.running = true;
        }
    }
    onSearchQueryChanged: debounce.restart()

    Process {
        id: searchProc
        stdout: StdioCollector {
            id: searchOut
            onStreamFinished: {
                root.searching = false;
                try {
                    const data = JSON.parse(searchOut.text || "{}");
                    const out = [];
                    for (const key in data) {
                        // key shape: "legacyPackages.x86_64-linux.<attr...>"
                        // -- strip the first two dotted components to get
                        // the real attribute path.
                        const parts = key.split(".");
                        const attr = parts.slice(2).join(".");
                        const info = data[key];
                        out.push({
                            attr,
                            pname: info.pname ?? attr,
                            version: info.version ?? "",
                            description: info.description ?? ""
                        });
                    }
                    out.sort((a, b) => a.attr.localeCompare(b.attr));
                    root.results = out.slice(0, 100);
                } catch (e) {
                    root.errorText = "search failed to parse -- try a different query";
                    root.results = [];
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.results.length === 0 && !root.searching)
                root.errorText = root.errorText || "nix search failed (network or query error)";
        }
    }

    property int _tryJobId: -1
    function tryNow(attr) {
        root._tryJobId = JobRunner.run(`Try ${attr}`, ["nix", "profile", "install", `nixpkgs#${attr}`], { privileged: false });
    }

    property string _addBusyAttr: ""
    function addToConfig(attr) {
        root._addBusyAttr = attr;
        PackageOps.addToConfig(attr, "user", (ok, message) => {
            root._addBusyAttr = "";
            if (!ok)
                console.warn(`InstallPackages: add "${attr}" failed -- ${message}`);
        });
    }

    component ActionButton: Rectangle {
        id: btn
        required property string label
        property bool disabled: false
        signal activated
        width: label_.implicitWidth + 16
        height: 22
        radius: Theme.radius.input
        opacity: btn.disabled ? 0.4 : 1
        color: (!btn.disabled && mouse.containsMouse) ? Theme.color.launcherItemSelectedBg : "transparent"
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
            hoverEnabled: !btn.disabled
            cursorShape: btn.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: if (!btn.disabled)
                btn.activated()
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 12

        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Type in the search box above to search nixpkgs. \"Add to config\" writes a declarative line into packages.nix (see the Pending tab); \"Try now\" installs imperatively via `nix profile`, outside git."
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Text {
            visible: root.searching
            text: "searching nixpkgs…"
            color: Theme.color.launcherPlaceholderFg
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Text {
            visible: root.errorText.length > 0
            text: root.errorText
            color: Theme.color.critical
            font.family: Theme.font.family
            font.pixelSize: Theme.font.sizeSmall
        }

        Repeater {
            model: root.results

            delegate: Column {
                id: resultRow
                required property var modelData
                readonly property bool declared: PackageDeclarations.isDeclared(resultRow.modelData.attr)
                readonly property bool nested: resultRow.modelData.attr.includes(".")
                width: column.width
                spacing: 2

                Row {
                    width: parent.width
                    spacing: 8

                    Column {
                        width: parent.width - 160
                        Row {
                            spacing: 6
                            Text { text: resultRow.modelData.pname; color: Theme.color.fg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall; font.bold: true }
                            Text { text: resultRow.modelData.version; color: Theme.color.launcherPlaceholderFg; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                            Text { visible: resultRow.declared; text: "declared"; color: Theme.color.accentPurple; font.family: Theme.font.family; font.pixelSize: Theme.font.sizeSmall }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: resultRow.modelData.description
                            color: Theme.color.launcherPlaceholderFg
                            font.family: Theme.font.family
                            font.pixelSize: Theme.font.sizeSmall
                        }
                    }

                    Row {
                        spacing: 6
                        ActionButton {
                            label: root._addBusyAttr === resultRow.modelData.attr ? "adding…" : "add to config"
                            disabled: resultRow.declared || resultRow.nested || root._addBusyAttr.length > 0
                            onActivated: root.addToConfig(resultRow.modelData.attr)
                        }
                        ActionButton {
                            label: "try now"
                            onActivated: root.tryNow(resultRow.modelData.attr)
                        }
                    }
                }
            }
        }
    }
}
