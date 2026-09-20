{ pkgs, config, ... }:

let
  home = config.home.homeDirectory;

  # The PWA's files still live at the repo root (they move under
  # quickshell/modules/qubi/mobile/ with the QML). Copied into the store so
  # the static server publishes exactly these four files -- it used to
  # serve the whole checkout, .git included, to the tailnet.
  mobileRoot = pkgs.runCommand "qubi-mobile-root" { } ''
    mkdir -p $out
    cp ${../../../mobile_gui.html} $out/mobile_gui.html
    cp ${../../../manifest.json} $out/manifest.json
    cp ${../../../icon-192.png} $out/icon-192.png
    cp ${../../../icon-512.png} $out/icon-512.png
  '';
in
{
  # Qubi is staged in-tree at the path its own repo will be mounted at, and
  # consumed exactly as it will be once it is a flake input:
  #   imports = [ inputs.qubi.homeModules.qubi ];
  imports = [ ../../../quickshell/modules/qubi/nix/hm-module.nix ];

  programs.qubi = {
    enable = true;
    defaultCwd = "${home}/nix-dots";
    shellPath = "${home}/nix-dots/quickshell";
    themesDir = "${home}/nix-dots/themes";
    voice.enable = true;
    # programs.qubi.goose.* is set in ./goose.nix.
  };

  services.qubi.engine = {
    # Written by modules/nixos/apps/ai-workstation.nix on every dock/
    # undock/gaming transition.
    hwStateFile = "/run/ai-workstation/state.json";
  };

  services.qubi.mobile = {
    enable = true;
    root = mobileRoot;
    tailscaleServe.enable = true;
  };
}
