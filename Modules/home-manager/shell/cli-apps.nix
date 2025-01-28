{ pkgs, ... }:
{
  home.packages = with pkgs; [
    minipro
    arduino-cli
    lutgen
  ];
}
