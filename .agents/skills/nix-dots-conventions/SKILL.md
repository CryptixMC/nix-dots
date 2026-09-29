---
name: nix-dots-conventions
description: Module layout, wrapper-script patterns, and hard-won Nix/home-manager gotchas specific to this flake. Load before editing any .nix file in this repo.
---

# nix-dots module conventions

## Flake structure
- `flake.nix` exposes `nixosConfigurations.carbon` (the NixOS system, host
  "carbon") and a **standalone** `homeConfigurations.cryptix`
  (`home-manager.lib.homeManagerConfiguration`) — home-manager is NOT
  wired in as a NixOS module. This means system and home config are two
  separate builds/switches: `nh os switch` vs `nh home switch` (or the
  non-destructive equivalents `nixos-rebuild build --flake .#carbon` and
  `nix build .#homeConfigurations.cryptix.activationPackage`).
- Module placement: `modules/nixos/{core,hardware,services,apps}/*.nix`
  for system-level config, `modules/home-manager/{core,shell,apps,wm}/*.nix`
  for user-level, `modules/style/stylix.nix` for both. Small settings go
  into an existing module (e.g. `services/common.nix`) rather than a new
  one-liner file. A new module gets imported explicitly in
  `hosts/carbon/configuration.nix` (system) or `hosts/carbon/home.nix`
  (home) — nothing auto-discovers files in these directories.

## Verification without a switch
- `nix flake check` — evaluates both configs, fast, catches Nix-level
  errors (type errors, missing attrs, assertion failures).
- `nix build .#homeConfigurations.cryptix.activationPackage --no-link
  --print-out-paths` / `nixos-rebuild build --flake .#carbon` — fully
  realizes the derivations without switching. Grab a built binary's real
  store path from the build log or by realizing its `.drv` directly with
  `nix-store --realise <path>.drv` to test it standalone.
- **A stale binary trap**: `find /nix/store -maxdepth 1 -iname "*foo*"`
  can return an old build from before a source edit — Nix never
  garbage-collects automatically. Always resolve a tool's path from a
  *fresh* build's own closure, not an ambient glob.
- Neither `nix flake check` nor a successful build catches QML runtime
  errors or live behavioral bugs
  (permission/PATH/sudo-matching issues) — those need live testing.

## Wrapper-script pattern
Custom CLIs are `pkgs.writeShellScriptBin "name" ''...''` with an explicit
`PATH=${lib.makeBinPath [ ... ]}:$PATH` listing every binary the script
calls. Real bugs already hit from getting this list wrong:
- Forgetting `pkgs.bash` → `env ... bash -lc "..."` fails with
  "bash: No such file or directory".
- Forgetting `pkgs.systemd` → bare `systemctl` calls fail.
- Including `pkgs.sudo` (the raw non-setuid store binary) *ahead* of the
  inherited PATH shadows the real `/run/wrappers/bin/sudo` and breaks
  privilege elevation silently (no error, just permission denied later).
  Don't put `pkgs.sudo` in an explicit PATH override at all — let the
  inherited PATH provide it.

## sudo NOPASSWD rules match literal strings, not resolved paths
`security.sudo.extraRules` NOPASSWD entries are exact-string command
matches — they do NOT follow PATH resolution. A rule granting
`${pkgs.systemd}/bin/systemctl start foo` will NOT match a script calling
bare `sudo systemctl start foo`, even though both resolve to the same
binary. Always call the exact absolute store path in the script that a
NOPASSWD rule was written for.

## `yq` into shell variables needs `-r`
Without `-r`, `yq` keeps the quoted-string style and embeds literal quote
characters in the value.

## `home.activation` ordering
Real, confirmed order: `writeBoundary` → custom `home.activation` scripts
→ `linkGeneration`. A custom activation script referencing a `home.file`
target's path will fail ("cannot stat") if it runs before
`linkGeneration` — use a direct `pkgs.writeText`/derivation store path
instead of the `home.file`-managed symlink target when an activation
script needs to read that content itself.

## QML errors are invisible to `nix flake check`
`nix flake check` only evaluates Nix. After a QML change, restart the shell
(`quickshell -p desktop/shell`) and read its log for load/type errors. For a
narrow static pass, `qmllint --incompatible-type error` (everything else
disabled) catches the one bug class that has crashed the live shell: a
boolean `anchors {}` block on a plain Rectangle/Item. Other qmllint
categories false-positive on Quickshell's C++-backed singletons.

QML directories under `desktop/shell/modules/` are directory imports; a
folder with singletons has its own `qmldir`. A file in a subfolder only sees
its own folder, so it needs `import ".."` (or the specific folder) to use
types defined elsewhere.
