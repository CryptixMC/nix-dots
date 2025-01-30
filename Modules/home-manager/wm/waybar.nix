{ pkgs, ... }:
{
  programs.waybar = {
    enable = true;
    style = {

    };
    settings = {

    };
  };

  home.packages = with pkgs; [
  ];
}
