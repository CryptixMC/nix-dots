{ pkgs, inputs, ... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";

  imports = [
    ../../Modules/home-manager/apps/git.nix
    ../../Modules/home-manager/shell/zsh.nix
    ../../Modules/home-manager/wm/hyprland.nix
    #../../Modules/home-manager/wm/hyprpanel.nix
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
  ];

  home.file = {

  };

  programs = {
    kitty.enable = true;
    wofi.enable = true;
  };

  wayland.windowManager.hyprland.settings = {
    monitor = ",preferred,auto,1";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
