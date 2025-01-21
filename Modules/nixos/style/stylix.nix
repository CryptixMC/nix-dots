{ pkgs, inputs, lib, ... }:

let
  theme = "catppuccin-mocha-emmet";
  themePath = "../../../../Themes/"+theme+"/colors.yaml";
  themePolarity = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../../Themes"+("/"+theme)+"/polarity.txt"));
  backgroundURL = builtins.readFile (./. + "../../../../Themes"+("/"+theme)+"/backgroundurl.txt");
  backgroundSha256 = builtins.readFile (./. + "../../../../Themes"+("/"+theme)+"/backgroundsha256.txt");
in
{
  stylix = {
    enable = true;
    autoEnable = true;

    image = pkgs.fetchurl {
      url = backgroundURL;
      sha256 = backgroundSha256;
    };

    cursor.package = inputs.rose-pine-hyprcursor;
    cursor.name = "rose-pine-hyprcursor";
    cursor.size = 24;

    polarity = themePolarity;

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
    base16Scheme = ./. + themePath;
    #base16Scheme = {
    #  scheme = "Catppuccin Mocha";
    #  author = "https://github.com/catppuccin/catppuccin";
    #  base00 = "1e1e2e"; # base
    #  base01 = "181825"; # mantle
    #  base02 = "313244"; # surface0
    #  base03 = "45475a"; # surface1
    #  base04 = "585b70"; # surface2
    #  base05 = "cdd6f4"; # text
    #  base06 = "f5e0dc"; # rosewater
    #  base07 = "b4befe"; # lavender
    #  base08 = "f38ba8"; # red
    #  base09 = "fab387"; # peach
    #  base0A = "f9e2af"; # yellow
    #  base0B = "a6e3a1"; # green
    #  base0C = "94e2d5"; # teal
    #  base0D = "89b4fa"; # blue
    #  base0E = "cba6f7"; # mauve
    #  base0F = "f2cdcd"; # flamingo
    #};
  };
}
