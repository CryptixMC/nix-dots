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
    readonly property string prismIconsDir: `${root.home}/.local/share/PrismLauncher/icons`

    property var steamManifests: ({})
    property var steamIcons: ({})
    property var prismInstances: ({})
    property var prismIcons: ({})
    property var prismSharedIcons: ({})
    property var prismGameIcons: ({})

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

    // Valve's own compatibility tooling (Proton builds, the Steam Linux
    // Runtime containers, Steamworks' shared redistributable installer)
    // shows up as a normal appmanifest_*.acf alongside real games -- there
    // is no local "type" field to distinguish them by (that lives in
    // appinfo.vdf, a binary VDF blob keyed across the whole Steam catalog,
    // not worth a parser for this). Valve's naming is consistent across
    // every Steam install though, so matching on it is reliable in
    // practice: every compat tool is named "Proton ..." or "Steam Linux
    // Runtime ...", and there is exactly one shared redistributables
    // installer, always with this exact name.
    function isCompatTool(name) {
        return name.startsWith("Proton") || name.startsWith("Steam Linux Runtime") || name === "Steamworks Common Redistributables";
    }

    readonly property var entries: {
        const steam = Object.values(root.steamManifests).filter(m => !root.isCompatTool(m.name ?? "")).map(m => ({
            id: `steam:${m.appid}`,
            launcher: "Steam",
            name: m.name ?? m.appid,
            iconSource: root.steamIcons[m.appid] ? root.fileUrl(root.steamIcons[m.appid]) : "",
            lastPlayed: parseInt(m.LastPlayed) || 0,
            // No reliable playtime source in the .acf manifests (see the
            // Prism entry below for why) -- 0 like an unplayed game, so
            // the card just omits the playtime badge.
            totalPlayedSecs: 0,
            launch: () => Quickshell.execDetached(["steam", `steam://rungameid/${m.appid}`])
        }));
        const prism = Object.values(root.prismInstances).map(p => ({
            id: `prism:${p.id}`,
            launcher: "Prism Launcher",
            name: p.name ?? p.id,
            // Three tiers, in order: a per-instance profileImage override
            // (rare), the shared icons/<iconKey>.png every modpack-
            // downloaded instance actually uses, then Minecraft's own
            // instance-root icon.png (written by the game itself after
            // first launch, recovers art for instances whose iconKey is
            // one of Prism's built-in names with no file on disk -- e.g.
            // "chicken"/"default"). Only instances that have never been
            // launched and use a built-in iconKey fall through all three,
            // landing on GamesTab.qml's Minecraft-glyph default instead of
            // the generic gamepad one.
            iconSource: root.prismIcons[p.id] ? root.fileUrl(root.prismIcons[p.id]) : (p.iconKey && root.prismSharedIcons[p.iconKey] ? root.fileUrl(root.prismSharedIcons[p.iconKey]) : (root.prismGameIcons[p.id] ? root.fileUrl(root.prismGameIcons[p.id]) : "")),
            // lastLaunchTime is milliseconds (Qt DateTime epoch), unlike
            // Steam's LastPlayed which is already whole seconds.
            lastPlayed: Math.floor((parseInt(p.lastLaunchTime) || 0) / 1000),
            // Whole seconds, same as Steam has no equivalent of (no
            // reliable playtime source exists in the .acf manifests this
            // grabs Steam's data from -- Steam only tracks it in
            // localconfig.vdf, a per-steamid nested VDF blob not worth
            // parsing for this). Games tab cards just omit the badge for
            // entries where this is 0.
            totalPlayedSecs: parseInt(p.totalTimePlayed) || 0,
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
    // per app. Three filenames, not one: confirmed real on this machine that
    // roughly half the library only has SOME of these cached (Steam fills
    // this cache lazily, from whatever its own client has actually
    // rendered) -- library_600x900.jpg is the classic portrait cover when
    // present, library_capsule.jpg is its modern per-asset-hash replacement
    // (same 2:3 portrait purpose, just a renamed asset type), and
    // library_header.jpg is a landscape fallback that's still far better
    // than the bare gamepad glyph for the handful of games Steam hasn't
    // cached anything portrait-shaped for yet.
    Process {
        running: true
        command: ["find", root.steamCacheDir, "-mindepth", "2", "(", "-iname", "library_600x900.jpg", "-o", "-iname", "library_capsule.jpg", "-o", "-iname", "library_header.jpg", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rank = {
                    "library_600x900.jpg": 0,
                    "library_capsule.jpg": 1,
                    "library_header.jpg": 2
                };
                const best = {};
                for (const line of text.split("\n").filter(l => l.length > 0)) {
                    const parts = line.split("/");
                    const idx = parts.indexOf("librarycache");
                    if (idx < 0 || !parts[idx + 1])
                        continue;
                    const appid = parts[idx + 1];
                    const r = rank[parts[parts.length - 1].toLowerCase()] ?? 9;
                    if (!best[appid] || r < best[appid].rank)
                        best[appid] = {
                            rank: r,
                            path: line
                        };
                }
                const icons = {};
                for (const appid in best)
                    icons[appid] = best[appid].path;
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
        command: ["sh", "-c", `grep -H -E '^(name|lastLaunchTime|totalTimePlayed|iconKey)=' ${root.prismInstancesDir}/*/instance.cfg 2>/dev/null`]
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

    // Shared icon library every modpack-downloaded instance actually draws
    // its icon from via instance.cfg's iconKey (confirmed real: 10 of 13
    // instances on this machine resolve this way, only 2 have a
    // profileImage override, and a couple more use Prism's own built-in
    // icon names with no file on disk at all). Keyed by filename stem so
    // `entries` above can look a given instance's iconKey straight up.
    Process {
        running: true
        command: ["find", root.prismIconsDir, "-maxdepth", "1", "-type", "f"]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = {};
                for (const line of text.split("\n").filter(l => l.length > 0)) {
                    const fname = line.split("/").pop();
                    const stem = fname.replace(/\.[^.]+$/, "");
                    icons[stem] = line;
                }
                root.prismSharedIcons = icons;
            }
        }
    }

    // Third and last icon tier: Minecraft itself writes an icon.png at the
    // instance's game-dir root (confirmed real: 12 of 13 instances on this
    // machine have one, including several whose iconKey points at a
    // built-in Prism name with no file on disk -- this recovers art for
    // exactly that gap). Dir name varies by instance vintage ("minecraft"
    // vs the older ".minecraft"), hence matching both; -maxdepth 3 keeps
    // this from ever descending into a world save or mod jar, which could
    // be gigabytes.
    Process {
        running: true
        command: ["find", root.prismInstancesDir, "-mindepth", "3", "-maxdepth", "3", "(", "-path", "*/minecraft/icon.png", "-o", "-path", "*/.minecraft/icon.png", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = {};
                for (const line of text.split("\n").filter(l => l.length > 0)) {
                    const parts = line.split("/");
                    icons[parts[parts.length - 3]] = line;
                }
                root.prismGameIcons = icons;
            }
        }
    }
}
