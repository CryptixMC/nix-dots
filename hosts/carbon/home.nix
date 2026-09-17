{ lib, ... }:
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
    ../../modules/home-manager/apps/goose.nix
    ../../modules/home-manager/apps/goose-bench.nix
    ../../modules/home-manager/apps/opencode.nix
    ../../modules/home-manager/apps/voice.nix
    ../../modules/style/stylix.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";
  home.stateVersion = "25.05";

  stylix.targets.zen-browser.enable = false;

  # Quickshell's own Wallpaper.qml owns the background layer now (see
  # modules/home-manager/wm/hyprland.nix's exec-once comment) — stylix's
  # hyprland target auto-enables hyprpaper whenever stylix.image != null,
  # which silently starts a `hyprpaper.service` systemd user unit racing
  # Wallpaper.qml for the same layer. Confirmed live: hyprpaper was still
  # running even though nothing in this repo's own exec-once execs it
  # anymore. Both overrides are required: the hyprland target's
  # `hyprpaper.enable` suboption directly sets `services.hyprpaper.enable
  # = true` AND `stylix.targets.hyprpaper.enable = true` as a side effect
  # (modules/hyprland/hm.nix in the stylix flake) — setting only the
  # standalone `targets.hyprpaper.enable` leaves `services.hyprpaper.
  # enable` untouched and hyprpaper keeps running. mkForce is needed
  # either way since the module sets both at normal priority.
  stylix.targets.hyprland.hyprpaper.enable = lib.mkForce false;
  stylix.targets.hyprpaper.enable = lib.mkForce false;

  home.file = {

  };

  programs.home-manager.enable = true;
}
