{ pkgs, ... }:
{
  home.packages = with pkgs; [
    kicad
    arduino
    fritzing
  ];
}
