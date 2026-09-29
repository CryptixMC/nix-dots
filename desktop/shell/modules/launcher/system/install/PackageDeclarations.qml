pragma Singleton
import QtQuick
import QtQml
import Quickshell
import Quickshell.Io

// Parses this repo's .nix package lists (no nix invocation) to get the
// exact attr names PackageOps writes back. Read-only; PackageOps is the
// write path. The two general sites are writable; six topical sites are
// parsed read-only since they contain callPackage entries and trailing
// comments a naive line edit would corrupt.
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

    // path -> [{attr, scope, file, readOnly}]. Reassembled into `declared`
    // on every update so consumers never see a half-loaded result.
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

    // Only scans inside the `systemPackages`/`home.packages` list span:
    // whole-file scans matched bash keywords (`fi`, `done`) in embedded
    // scripts. Within it, only a bare identifier alone on its line (after
    // stripping a trailing `#` comment) counts.
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

            // Reassign `_perSite`, never mutate it in place: a keyed write fires no
            // change notification and `loaded` would never update.
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
