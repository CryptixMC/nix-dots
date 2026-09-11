{ pkgs, ... }:
{
  stylix = {
    enable = true;

    image = ../../themes/ultraviolet/wallpapers/alyssa.png;
    base16Scheme = ../../themes/ultraviolet/base16.yaml;
    polarity = "dark";
    targets.qt.enable = false;
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Sans";
      };
      serif = {
        package = pkgs.dejavu_fonts;
        name = "DejaVu Serif";
      };
    };
  };
}
