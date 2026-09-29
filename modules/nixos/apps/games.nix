{ pkgs, ... }:
let
  # Launch-option wrapper forcing real fullscreen at the eGPU monitor's native
  # resolution. GPU selection is set globally in hyprland.nix.
  gamescopeEgpu = pkgs.writeShellScriptBin "gamescope-egpu" ''
    set -euo pipefail

    # GAMESCOPE_EGPU_ARGS overrides the defaults (gamescope keeps the last value of a flag).
    gamescope_args=(-W 1920 -H 1080 -f)
    if [ -n "''${GAMESCOPE_EGPU_ARGS-}" ]; then
      # shellcheck disable=SC2206
      gamescope_args+=($GAMESCOPE_EGPU_ARGS)
    fi

    # Steam's %command% starts with "--"; other launchers don't. Without exactly
    # one "--", gamescope misparses game args like JVM long options as its own.
    if [ "''${1-}" = "--" ]; then
      exec ${pkgs.gamescope}/bin/gamescope "''${gamescope_args[@]}" "$@"
    else
      exec ${pkgs.gamescope}/bin/gamescope "''${gamescope_args[@]}" -- "$@"
    fi
  '';
in
{
  environment.systemPackages = with pkgs; [
    prismlauncher
    #lutris
    gamescope
    gamescopeEgpu
    (pkgs.callPackage ../../../pkgs/kitten-space-agency { })
  ];

  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    # SteamOS-style session: the whole Steam client in one gamescope instance,
    # so games need no per-game setup. Launched nested via SUPER+G (hyprland.nix).
    gamescopeSession = {
      enable = true;
      args = [
        "-W"
        "1920"
        "-H"
        "1080"
        "-f"
      ];
      env = {
        MESA_VK_DEVICE_SELECT = "1002:73bf";
        DRI_PRIME = "0000:54:00.0";
      };
    };
  };
}
