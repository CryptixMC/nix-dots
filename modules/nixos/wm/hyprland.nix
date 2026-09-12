{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  environment.systemPackages = with pkgs; [
    kitty
    hyprpaper
    wofi
    xcursor-pro
    kanshi
    # walker # hidden, not removed — Quickshell's launcher (see TODO.md §3)
    # is the default now (SUPER+R); re-add to roll back.
    pavucontrol
    polkit_gnome
  ];
}
