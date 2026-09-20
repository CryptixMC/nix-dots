{ pkgs, lib, config, ... }:

let
  # The engine, its CLIs (qubi-config / qubi-models / qubi-bench /
  # qubi-hwstate) and the three stdio MCP servers are one real Python
  # package now, staged at its future repo root (quickshell/modules/qubi/,
  # see that tree's README). websockets + pyyaml are declared once in its
  # pyproject.toml rather than in a withPackages here.
  qubi = pkgs.callPackage ../../../quickshell/modules/qubi/nix/package.nix { };

  # Everything host-specific the package refuses to hardcode (see
  # python/src/qubi/paths.py). Exported on the unit AND baked into a
  # wrapper-free session environment so the CLIs a human runs by hand
  # (qubi-bench, qubi-hwstate) resolve the same locations the daemon does.
  qubiEnv = {
    QUBI_DEFAULT_CWD = "${config.home.homeDirectory}/nix-dots";
    QUBI_THEMES_DIR = "${config.home.homeDirectory}/nix-dots/themes";
    QUBI_SHELL_PATH = "${config.home.homeDirectory}/nix-dots/quickshell";
    # Written by modules/nixos/apps/ai-workstation.nix.
    QUBI_HW_STATE_FILE = "/run/ai-workstation/state.json";
  };
in
{
  home.packages = [ qubi ];

  home.sessionVariables = qubiEnv;

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
    run ${qubi}/bin/qubi-config init
  '';

  # Same WebSocket port (8765) and "always on for mobile" role the old
  # qubi-bridge.service had, backed by the real multi-tier engine.
  # Restart=on-failure (not "always" -- a crash-looping engine shouldn't
  # hammer Ollama in a tight restart loop) and After=graphical-session.target
  # since it needs a live Hyprland session for the same reasons
  # goose-state-sync's own notify path does (though the engine itself
  # doesn't call hyprctl directly, its warm-up Ollama call and tier
  # processes assume a real user session is up).
  systemd.user.services.qubi-engine = {
    Unit = {
      Description = "Qubi engine: persistent multi-tier goose acp router (unix socket + websocket)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${qubi}/bin/qubi-engine";
      Environment = lib.mapAttrsToList (k: v: "${k}=${v}") qubiEnv ++ [ "PYTHONUNBUFFERED=1" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
