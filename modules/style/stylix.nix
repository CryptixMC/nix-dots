{ pkgs, ... }:
{
  stylix = {
    enable = true;

    image = ../../desktop/themes/ultraviolet/wallpapers/alyssa.png;
    base16Scheme = ../../desktop/themes/ultraviolet/base16.yaml;
    polarity = "dark";
    targets.qt.enable = false;
    # Imported by both NixOS and home-manager: only options valid in both belong
    # here. Home-manager-only targets (e.g. hyprland.hyprpaper) go in hosts/carbon/home.nix.
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
