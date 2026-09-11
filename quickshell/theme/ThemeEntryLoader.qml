import QtQuick
import Quickshell.Io

// Loads one theme folder (base16.yaml + optional theme.json + optional
// components/) and assembles it into the token-tree shape Theme.qml
// exposes, via ThemeDefaults.build(). base16.yaml is the only mandatory
// piece — theme.json and components/ are both genuinely optional, and
// loaded() re-fires (harmlessly — ThemeLoader just overwrites its entry)
// as each independent async source settles, so a colors-only theme
// resolves as soon as its base16.yaml's yq Process finishes, without
// waiting on anything else.
Item {
    id: root

    required property string themeName
    required property string themesDir
    readonly property string themeDir: `${themesDir}/${themeName}`

    signal loaded(string name, var data)

    property var base16Data: null
    property var manifestData: ({})
    property var componentOverrides: ({})

    function tryEmit() {
        if (root.base16Data === null)
            return;
        root.loaded(root.themeName, ThemeDefaults.build(root.base16Data, root.manifestData, root.componentOverrides, root.themeDir));
    }

    Process {
        running: true
        command: ["yq", "-o=json", "-I=0", `${root.themeDir}/base16.yaml`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.base16Data = JSON.parse(text);
                } catch (e) {
                    console.warn(`ThemeEntryLoader: failed to parse base16.yaml for "${root.themeName}": ${e}`);
                    root.base16Data = {};
                }
                root.tryEmit();
            }
        }
    }

    FileView {
        path: `${root.themeDir}/theme.json`
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                root.manifestData = JSON.parse(text());
            } catch (e) {
                console.warn(`ThemeEntryLoader: failed to parse theme.json for "${root.themeName}": ${e}`);
                root.manifestData = {};
            }
            root.tryEmit();
        }
        onLoadFailed: error => {
            // No theme.json at all is a valid colors-only theme, not an
            // error — themes/ultraviolet/ ships none, proving this path.
            root.manifestData = {};
            root.tryEmit();
        }
    }

    // components/ is optional too — `find` against a missing directory
    // just errors on stderr and produces empty stdout, which reads
    // identically to "this theme has no component overrides".
    Process {
        running: true
        command: ["find", `${root.themeDir}/components`, "-maxdepth", "1", "-name", "*.qml", "-printf", "%f\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").filter(n => n.length > 0);
                const overrides = {};
                for (const n of names)
                    overrides[n.replace(/\.qml$/, "")] = `file://${root.themeDir}/components/${n}`;
                root.componentOverrides = overrides;
                root.tryEmit();
            }
        }
    }
}
