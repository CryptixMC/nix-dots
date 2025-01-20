{ pkgs,... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";

  imports = [
    ../../Modules/home-manager/apps/git.nix
    ../../Modules/home-manager/shell/zsh.nix
  ];

  home.packages = [
    pkgs.cargo
    pkgs.rustc
    pkgs.rust-analyzer
    pkgs.nixd
    pkgs.gcc
    pkgs.bottom
    pkgs.eza
    pkgs.fd
    pkgs.onefetch
    pkgs.prismlauncher
    pkgs.gfn-electron
    pkgs.prusa-slicer
    pkgs.hyprpaper
  ];

  home.file = {

  };

  programs = {
    kitty.enable = true;
    #waybar
    wofi.enable = true;
    #hyprland
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
