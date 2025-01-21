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
  };
}
