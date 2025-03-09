{ pkgs, ... }:
{
  home.packages = with pkgs; [
    prusa-slicer
    blender
    krita
    inkscape
    libresprite
    material-maker
    tenacity
    gimp
  ];
}
