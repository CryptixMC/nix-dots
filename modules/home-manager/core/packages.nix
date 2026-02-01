{ pkgs, ... }:
{
  imports = [
    ../apps/it-tools.nix
  ];

  home.packages = with pkgs; [
    mangohud
    neovim
    prismlauncher
    brightnessctl
    nixd
    nil
    vinegar
    obs-studio
    blender
    zoom-us
    cura
    super-slicer
  ];
}
