{ pkgs, config, ... }:

let
  home = config.home.homeDirectory;

  # The PWA itself comes from the qubi tree. The only thing added here is
  # the URL it used to live at, which the copy installed on the phone still
  # has as its start_url. (Served from the store: the static server used to
  # publish the whole checkout, .git included, to the tailnet.)
  mobileRoot = pkgs.runCommand "qubi-mobile-root" { } ''
    mkdir -p $out
    cp -r ${pkgs.callPackage ../../../quickshell/modules/qubi/nix/mobile.nix { }}/. $out/
    ln -s index.html $out/mobile_gui.html
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
