{ pkgs, lib, ... }:

let
  # engine/ (repo root, sibling to goose_bridge.py which it supersedes) is
  # tonight's new code: the runtime config CLI, the engine daemon itself
  # (Phase 2), and the escalate MCP server (Phase 3) all live there as
  # plain Python -- same "no build step, read straight from the repo"
  # choice goose_bridge.py already made, now shared by everything that
  # isn't QML. pythonEnv is the one place the `websockets` dependency is
  # declared; every script below that needs it shares this exact env so
  # there's no risk of one of them silently running against a bare
  # system python3 that lacks it (goose.nix's own gooseMobileBridge comment
  # already flagged this exact trap for goose_bridge.py).
  pythonEnv = pkgs.python3.withPackages (p: [ p.websockets ]);

  qubiConfigCli = pkgs.writeShellScriptBin "qubi-config" ''
    exec ${pythonEnv}/bin/python3 ${../../../engine/qubi_config.py} "$@"
  '';
in
{
  home.packages = [
    qubiConfigCli
  ];

  # Writes ~/.config/qubi/config.json ONLY if it doesn't already exist --
  # this is the one config file in this whole repo that a `home-manager
  # switch` must NEVER clobber, because Phase 1's whole point is that Liam
  # (or a future settings UI) can edit tiers/routing/theme live without a
  # rebuild. Contrast gooseConfigInit in goose.nix, which unconditionally
  # overwrites config.yaml (backing up drift first) -- that file is meant
  # to stay Nix-authoritative; this one is meant to stay user-authoritative
  # after its first write. `qubi-config init` (not `--force`) already
  # implements the same no-clobber guard, so this activation snippet is a
  # one-line call into the same logic rather than a second implementation
  # of it.
  home.activation.qubiConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${qubiConfigCli}/bin/qubi-config init
  '';
}
