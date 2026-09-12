pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Steam + Prism Launcher discovery, merged into one `entries` list. Modeled
// on ThemeLoader.qml's discover-then-merge pattern, but simpler — each
// adapter is just two independent Process calls (manifest/instance data,
// then icon paths) cross-referenced by id in JS, no per-item Process spawn.
// Adding a third launcher later means one more pair of Process blocks plus
// one more branch in `entries` — no plugin/script-file system, since there
// are exactly two real launchers installed today (Lutris/Heroic aren't) and
// a heavier abstraction would be speculative.
Item {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string steamAppsDir: `${root.home}/.local/share/Steam/steamapps`
    readonly property string steamCacheDir: `${root.home}/.local/share/Steam/appcache/librarycache`
    readonly property string prismInstancesDir: `${root.home}/.local/share/PrismLauncher/instances`

    property var steamManifests: ({})
    property var steamIcons: ({})
    property var prismInstances: ({})
    property var prismIcons: ({})

    // Instance/directory names are free text and can contain characters a
    // `file://` URL string doesn't handle cleanly here (confirmed real on
    // this machine: "Arcadia [RPG] new" broke Image.source with brackets
    // and a space even after encodeURI-escaping them — Qt's own file URL
    // parsing of the resulting percent-encoded string still failed to
    // resolve to the real path). Bare absolute paths sidestep URL parsing
    // entirely — Qt Quick's Image.source treats a plain "/..." string as a
    // local file directly, so there's no encoding question at all.
    function fileUrl(absolutePath) {
        return absolutePath;
    }

    readonly property var entries: {
        const steam = Object.values(root.steamManifests).map(m => ({
            id: `steam:${m.appid}`,
            launcher: "Steam",
            name: m.name ?? m.appid,
            iconSource: root.steamIcons[m.appid] ? root.fileUrl(root.steamIcons[m.appid]) : "",
            lastPlayed: parseInt(m.LastPlayed) || 0,
            launch: () => Quickshell.execDetached(["steam", `steam://rungameid/${m.appid}`])
        }));
        const prism = Object.values(root.prismInstances).map(p => ({
            id: `prism:${p.id}`,
            launcher: "Prism Launcher",
            name: p.name ?? p.id,
            iconSource: root.prismIcons[p.id] ? root.fileUrl(root.prismIcons[p.id]) : "",
            // lastLaunchTime is milliseconds (Qt DateTime epoch), unlike
            // Steam's LastPlayed which is already whole seconds.
            lastPlayed: Math.floor((parseInt(p.lastLaunchTime) || 0) / 1000),
            launch: () => Quickshell.execDetached(["prismlauncher", "-l", p.id])
        }));
        return steam.concat(prism);
    }

    // Steam manifests: shallow top-level "AppState" keys only, parsed with
    // one grep across every appmanifest_*.acf at once rather than spawning
    // a Process per app. Lines interleave file-by-file (grep processes one
    // full file before the next), so grouping by the "-H" filename prefix
    // first, then reducing to one record per appid, recovers the per-app
    // grouping correctly.
    Process {
        running: true
        command: ["sh", "-c", `grep -H -E '"appid"|"name"|"LastPlayed"' ${root.steamAppsDir}/appmanifest_*.acf 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const byPath = {};
                for (const line of text.split("\n")) {
                    const m = line.match(/^(.*?):\s*"(\w+)"\s+"([^"]*)"/);
                    if (!m)
                        continue;
                    const [, path, key, value] = m;
                    if (!byPath[path])
                        byPath[path] = {};
                    byPath[path][key] = value;
                }
                const byAppid = {};
                for (const data of Object.values(byPath))
                    if (data.appid)
                        byAppid[data.appid] = data;
                root.steamManifests = byAppid;
            }
        }
    }

    // One `find` for every app's cover art at once (`<appid>/<hash>/
    // library_600x900.jpg` — the hash subdirectory isn't derivable from the
    // appid alone), cross-referenced by appid in JS rather than one `find`
    // per app.
    Process {
        running: true
        command: ["find", root.steamCacheDir, "-mindepth", "2", "-iname", "library_600x900.jpg"]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = {};
                for (const line of text.split("\n").filter(l => l.length > 0)) {
                    const parts = line.split("/");
                    const idx = parts.indexOf("librarycache");
                    if (idx >= 0 && parts[idx + 1])
                        icons[parts[idx + 1]] = line;
                }
                root.steamIcons = icons;
            }
        }
    }

    // Prism instance.cfg is INI, not JSON — same one-grep-across-every-file
    // approach as the Steam manifests above, grouped by the "-H" filename
    // prefix (the instance directory name, which can contain spaces —
    // shell globbing in the `sh -c` below handles that natively, and
    // splitting the grep-reported path on "/" preserves it correctly).
    Process {
        running: true
        command: ["sh", "-c", `grep -H -E '^(name|lastLaunchTime|totalTimePlayed)=' ${root.prismInstancesDir}/*/instance.cfg 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const byPath = {};
                for (const line of text.split("\n")) {
                    const m = line.match(/^(.*?):([a-zA-Z]+)=(.*)$/);
                    if (!m)
                        continue;
                    const [, path, key, value] = m;
                    if (!byPath[path])
                        byPath[path] = {};
                    byPath[path][key] = value;
                }
                const byId = {};
                for (const [path, data] of Object.entries(byPath)) {
                    const parts = path.split("/");
                    const id = parts[parts.length - 2];
                    byId[id] = Object.assign({ id }, data);
                }
                root.prismInstances = byId;
            }
        }
    }

    // Per-instance icon override — confirmed real on this machine for some
    // instances; instances without one fall back to a generic glyph in
    // GamesTab.qml's card delegate. `profileImage` is itself a directory
    // (confirmed real: contains exactly one arbitrarily-named image file,
    // not an image itself) — one level deeper than the naive "does this
    // instance have a profileImage" check would suggest, so this searches
    // *inside* it for the actual file rather than treating the directory
    // as the icon.
    Process {
        running: true
        command: ["find", root.prismInstancesDir, "-mindepth", "3", "-maxdepth", "3", "-path", "*/profileImage/*", "-type", "f"]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = {};
                for (const line of text.split("\n").filter(l => l.length > 0)) {
                    const parts = line.split("/");
                    icons[parts[parts.length - 3]] = line;
                }
                root.prismIcons = icons;
            }
        }
    }
}
