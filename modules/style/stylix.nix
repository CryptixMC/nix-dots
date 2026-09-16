{ pkgs, ... }:
{
  stylix = {
    enable = true;

    image = ../../themes/ultraviolet/wallpapers/alyssa.png;
    base16Scheme = ../../themes/ultraviolet/base16.yaml;
    polarity = "dark";
    targets.qt.enable = false;
    # NOTE: this file is imported at BOTH the NixOS level (configuration.nix,
    # for system-level theming) and the home-manager level (home.nix) — only
    # options that exist in both module trees belong here. Home-manager-only
    # target overrides (e.g. hyprpaper) go in hosts/carbon/home.nix instead,
    # next to the existing `stylix.targets.zen-browser.enable = false;` —
    # confirmed the hard way: `targets.hyprland.hyprpaper.enable` here broke
    # `nixos-rebuild` with "The option `stylix.targets.hyprland' does not
    # exist" since that sub-option is home-manager-only.
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
