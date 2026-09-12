{ pkgs, ... }:
let
  # Wrapper for game launch options: forces real fullscreen at the
  # eGPU-attached DP-6 output's native resolution (not just "fullscreen"
  # inside a small nested window — see README/hyprland.nix). Device
  # selection itself no longer needs to live here — MESA_VK_DEVICE_SELECT
  # and DRI_PRIME are set globally in hyprland.nix and apply to every
  # Vulkan/OpenGL app automatically, eGPU or not.
  gamescopeEgpu = pkgs.writeShellScriptBin "gamescope-egpu" ''
    set -euo pipefail

    # Override per-launch with GAMESCOPE_EGPU_ARGS, e.g.
    # `GAMESCOPE_EGPU_ARGS="-W 2560 -H 1440" gamescope-egpu -- %command%`
    # — gamescope keeps the last value it sees for a repeated flag, so args
    # appended after these defaults win.
    gamescope_args=(-W 1920 -H 1080 -f)
    if [ -n "''${GAMESCOPE_EGPU_ARGS-}" ]; then
      # shellcheck disable=SC2206
      gamescope_args+=($GAMESCOPE_EGPU_ARGS)
    fi

    # Steam's %command% expansion already includes a leading "--", but other
    # launchers hand us the game's command line with no separator at all.
    # Gamescope's option parser keeps scanning past the first non-option
    # word looking for more flags of its own, so a later argument that
    # looks like a long option (e.g. a JVM flag such as
    # --sun-misc-unsafe-memory-access=allow) gets misread as an
    # unrecognized gamescope option unless exactly one "--" terminates
    # gamescope's own argv first.
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
    # Valve's own "whole Steam client + every game in one gamescope
    # instance" session (SteamOS/Deck-style) — the actual fix for needing
    # to configure every game individually, rather than a custom script.
    # Reachable via the GDM session picker (bypassed by this host's
    # autologin/defaultSession — see xserver.nix) or, day-to-day, via the
    # SUPER+G keybind in hyprland.nix which runs the equivalent command
    # nested inside the normal Hyprland session.
    gamescopeSession = {
      enable = true;
      args = [ "-W" "1920" "-H" "1080" "-f" ];
      env = {
        MESA_VK_DEVICE_SELECT = "1002:73bf";
        DRI_PRIME = "0000:54:00.0";
      };
    };
  };
}
