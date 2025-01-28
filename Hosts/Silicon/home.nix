{ pkgs,... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";

  imports = [
    ../../Modules/home-manager/apps/git.nix
    ../../Modules/home-manager/shell/zsh.nix
    ../../Modules/home-manager/wm/hyprland.nix
    ../../Modules/home-manager/shell/cli-apps.nix
  ];

  home.packages = with pkgs; [
    cargo
    rustc
    rust-analyzer
    nixd
    gcc
    bottom
    eza
    fd
    onefetch
    prismlauncher
    gfn-electron
    prusa-slicer
    hyprpaper
    gimp

  ];

  home.file = {

  };

  programs = {
    kitty.enable = true;
    #waybar
    wofi.enable = true;
  };

  wayland.windowManager.hyprland.settings = {
    monitor = [
      "HDMI-A-1,preferred,0x0,1"
      "DP-1,preferred,-1920x0,1"
    ];
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
