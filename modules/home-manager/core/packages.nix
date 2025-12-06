{ pkgs, ... }:
{
  imports = [
    ../apps/it-tools.nix
  ];

  home.packages = with pkgs; [
    neovim
    prismlauncher
    brightnessctl
    nixd
    nil
    vinegar
    obs-studio
    blender
    zoom-us
    openjdk
  ];
}
