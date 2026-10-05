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
    ../../modules/home-manager/apps/egpu-fault-guard.nix
    ../../modules/home-manager/apps/qubi.nix
    ../../modules/home-manager/apps/claude-usage.nix
    ../../modules/home-manager/apps/agents.nix

    ../../modules/style/stylix.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";
  home.stateVersion = "25.05";

  stylix.targets.zen-browser.enable = false;

  # Quickshell draws the wallpaper; stylix's hyprland target would enable hyprpaper
  # to race it. Both overrides are needed since that target sets both options.
  stylix.targets.hyprland.hyprpaper.enable = lib.mkForce false;
  stylix.targets.hyprpaper.enable = lib.mkForce false;

  programs.home-manager.enable = true;
}
