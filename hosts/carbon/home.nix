{ ... }:
{
  imports = [
    ../../modules/home-manager/core/packages.nix
    ../../modules/home-manager/core/variables.nix
    ../../modules/home-manager/apps/ghostty.nix
    # Hidden, not removed: Quickshell's launcher (quickshell/, see TODO.md
    # §3) is the default now, bound to SUPER+R. Re-add this import (and the
    # walker+elephant packages, see hosts' package lists) to roll back.
    # ../../modules/home-manager/apps/walker.nix
    ../../modules/home-manager/shell/zsh.nix
    ../../modules/home-manager/wm/hyprland.nix
    ../../modules/home-manager/wm/kanshi.nix
    ../../modules/home-manager/wm/waybar.nix
    ../../modules/home-manager/apps/zen-browser.nix
    ../../modules/home-manager/apps/zed.nix
    ../../modules/style/stylix.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";
  home.stateVersion = "25.05";

  stylix.targets.zen-browser.enable = false;

  home.file = {

  };

  programs.home-manager.enable = true;
}
