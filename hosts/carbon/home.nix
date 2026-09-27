{ lib, ... }:
{
  imports = [
    ../../modules/home-manager/core/packages.nix
    ../../modules/home-manager/core/variables.nix

    ../../modules/home-manager/shell/zsh.nix

    ../../modules/home-manager/wm/hyprland.nix
    ../../modules/home-manager/wm/kanshi.nix

    ../../modules/home-manager/apps/ghostty.nix
    ../../modules/home-manager/apps/zen-browser.nix
    ../../modules/home-manager/apps/zed.nix
    ../../modules/home-manager/apps/qubi-hwstate.nix
    ../../modules/home-manager/apps/qubi.nix
    ../../modules/home-manager/apps/claude-usage.nix

    ../../modules/style/stylix.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";
  home.stateVersion = "25.05";

  stylix.targets.zen-browser.enable = false;

  # Quickshell's Wallpaper.qml owns the background layer; stylix's hyprland target
  # auto-enables hyprpaper.service, racing it for the same layer. Both overrides are
  # required -- the hyprland target sets both services.hyprpaper.enable and
  # stylix.targets.hyprpaper.enable as a side effect (stylix's modules/hyprland/hm.nix).
  stylix.targets.hyprland.hyprpaper.enable = lib.mkForce false;
  stylix.targets.hyprpaper.enable = lib.mkForce false;

  home.file = {

  };

  programs.home-manager.enable = true;
}
