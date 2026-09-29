import QtQuick
import Quickshell.Io

// Loads one theme folder (base16.yaml required; theme.json and components/
// optional) via ThemeDefaults.build(). loaded() re-fires as each async source
// settles, so a theme resolves as soon as base16.yaml is parsed.
Item {
    id: root

    required property string themeName
    required property string themesDir
    readonly property string themeDir: `${themesDir}/${themeName}`

    signal loaded(string name, var data)

    property var base16Data: null
    property var manifestData: ({})
    property var componentOverrides: ({})
    property var wallpaperFiles: []

    function tryEmit() {
        if (root.base16Data === null)
            return;
        root.loaded(root.themeName, ThemeDefaults.build(root.base16Data, root.manifestData, root.componentOverrides, root.themeDir, root.wallpaperFiles));
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
            // No theme.json is a valid colors-only theme.
            root.manifestData = {};
            root.tryEmit();
        }
    }

    // A missing components/ just yields empty output, i.e. no overrides.
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

    // Plain image/gif files for the Themes tab picker. Shaders are excluded: they
    // need uniforms a plain click can't supply.
    Process {
        running: true
        command: ["find", `${root.themeDir}/wallpapers`, "-maxdepth", "1", "-xtype", "f", "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.gif", ")", "-printf", "%f\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wallpaperFiles = text.split("\n").filter(n => n.length > 0);
                root.tryEmit();
            }
        }
    }
}
