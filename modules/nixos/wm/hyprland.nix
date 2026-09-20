{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  environment.systemPackages = with pkgs; [
    xcursor-pro
    kanshi
    pavucontrol
    polkit_gnome
  ];
}
