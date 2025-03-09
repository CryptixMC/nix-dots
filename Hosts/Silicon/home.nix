{ pkgs,... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";

  imports = [
    ../../Modules/home-manager/apps/git.nix
    ../../Modules/home-manager/shell/zsh.nix
    ../../Modules/home-manager/wm/hyprland.nix
    ../../Modules/home-manager/shell/cli-apps.nix
    ../../Modules/home-manager/apps/electronics.nix
    ../../Modules/home-manager/apps/satelites.nix
    ../../Modules/home-manager/apps/programming.nix
    ../../Modules/home-manager/apps/gamedev.nix
    ../../Modules/home-manager/apps/games.nix
    ../../Modules/home-manager/apps/creating.nix
  ];

  home.packages = with pkgs; [
    hyprpaper
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
