pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

// Parses this repo's own .nix package lists -- the authoritative "what's
// declared" source, instant (no nix invocation at all), and the only thing
// that yields the exact attribute names PackageOps needs to write back.
// Read-only: this file only ever reads. modules/launcher/PackageOps.qml
// (the write path) is a separate singleton so the two responsibilities
// can't accidentally blur.
//
// Two general sites (user/system) are writable targets; six topical sites
// are parsed read-only so the Installed view can show "declared in
// apps/games.nix" without ever offering to edit them -- several contain
// `(pkgs.callPackage ../../../pkgs/foo { })` entries and trailing `#`
// comments that a naive line-edit would corrupt.
Item {
    id: root

    readonly property string repoRoot: `${Quickshell.env("HOME")}/nix-dots`

    readonly property var sites: [
        { path: "modules/home-manager/core/packages.nix", scope: "user", readOnly: false },
        { path: "modules/nixos/core/packages.nix", scope: "system", readOnly: false },
        { path: "modules/nixos/apps/games.nix", scope: "system", readOnly: true },
        { path: "modules/nixos/apps/docker.nix", scope: "system", readOnly: true },
        { path: "modules/nixos/wm/hyprland.nix", scope: "system", readOnly: true },
        { path: "modules/nixos/services/desktop-support.nix", scope: "system", readOnly: true },
        { path: "modules/nixos/hardware/amd.nix", scope: "system", readOnly: true },
        { path: "modules/nixos/hardware/thinkpad-power.nix", scope: "system", readOnly: true }
    ]

    // path -> [{attr, scope, file, readOnly}], filled in as each FileView's
    // async load settles -- reassembled into the flat `declared` array on
    // every update rather than read piecemeal, so a consumer never sees a
    // half-populated result from only some sites having loaded yet.
    property var _perSite: ({})
    property var declared: []
    readonly property bool loaded: Object.keys(root._perSite).length >= root.sites.length

    function _reassemble() {
        const out = [];
        for (const site of root.sites) {
            const entries = root._perSite[site.path];
            if (entries)
                out.push(...entries);
        }
        root.declared = out;
    }

    // Only scans INSIDE the actual `environment.systemPackages = ... [` /
    // `home.packages = ... [` span, from that opener line to its matching
    // `];` -- confirmed live this session that scanning the WHOLE file
    // (the original approach) produces false positives on the six
    // read-only topical sites: hardware/amd.nix's eGPU hotplug systemd
    // scripts are full of bare `fi`/`done`/`break`/`else` lines (bash
    // control-flow keywords, alone on their own line same as a real
    // package name would be), and every one of them passed the old
    // bare-identifier regex. Restricting the scan to the list's own line
    // range makes those keywords simply never examined, rather than
    // trying to denylist bash keywords by name (fragile, and a new script
    // block could introduce a keyword that collides with a real future
    // package name).
    //
    // Only a BARE identifier alone on its own line (after stripping a
    // trailing `#` comment) counts within that span -- deliberately
    // excludes `with pkgs;` itself, `(pkgs.callPackage ... )` entries,
    // comment-only lines, and the `[`/`]` list delimiters. Nix attribute
    // names can contain letters, digits, underscore, apostrophe and hyphen
    // (amdgpu_top, lsp-plugins, google-chrome all appear in this repo's
    // own lists).
    function _parseFile(text, site) {
        const out = [];
        let inList = false;
        for (const raw of text.split("\n")) {
            let line = raw.trim();
            if (!inList) {
                if (/(environment\.systemPackages|home\.packages)\s*=.*\[\s*$/.test(line))
                    inList = true;
                continue;
            }
            if (line === "];" || line === "]") {
                inList = false;
                continue;
            }
            if (line.length === 0 || line.startsWith("#") || line.startsWith("("))
                continue;
            if (line.includes("with pkgs"))
                continue;
            const hashIdx = line.indexOf("#");
            if (hashIdx >= 0)
                line = line.slice(0, hashIdx).trim();
            if (line.length === 0)
                continue;
            if (!/^[a-zA-Z_][a-zA-Z0-9_'-]*$/.test(line))
                continue;
            out.push({ attr: line, scope: site.scope, file: site.path, readOnly: site.readOnly });
        }
        return out;
    }

    function isDeclared(attr) {
        return root.declared.some(d => d.attr === attr);
    }

    function find(attr) {
        return root.declared.find(d => d.attr === attr) ?? null;
    }

    function reload() {
        root._perSite = {};
        for (let i = 0; i < instantiator.count; i++)
            instantiator.objectAt(i).reload();
    }

    Instantiator {
        id: instantiator
        model: root.sites

        delegate: FileView {
            id: fileDelegate
            required property var modelData
            path: `${root.repoRoot}/${modelData.path}`
            watchChanges: false
            printErrors: false

            // `_perSite` is REASSIGNED (Object.assign into a fresh object),
            // never mutated as `_perSite[key] = ...` in place -- an in-place
            // keyed write doesn't fire `_perSite`'s own change notification,
            // which silently broke `loaded`'s binding (confirmed live: count
            // reached the correct 130 entries via the eager `_reassemble()`
            // call below, which reads _perSite fresh each time regardless,
            // but `loaded` itself stayed permanently false). Same footgun
            // UsageStore.qml and SystemStats.qml's ring buffers document
            // elsewhere in this repo, this time on a keyed object rather
            // than an array.
            onLoaded: {
                root._perSite = Object.assign({}, root._perSite, { [fileDelegate.modelData.path]: root._parseFile(text(), fileDelegate.modelData) });
                root._reassemble();
            }
            onLoadFailed: error => {
                console.warn(`PackageDeclarations: failed to read "${fileDelegate.path}": ${error}`);
                root._perSite = Object.assign({}, root._perSite, { [fileDelegate.modelData.path]: [] });
                root._reassemble();
            }
        }
    }
}
