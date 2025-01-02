{ config, lib, pkgs, inputs, ... }:

let
  themePath = "../../../Themes/catpuccin-mocha/catppuccin-mocha.yaml";
  themePolarity = lib.removeSuffix "\n" (builtins.readFile (./. + "../../../Themes/catppuccin-mocha/polarity.txt"));
  backgroundUrl = builtins.readFile (./. + "../../../Themes/catppuccin-mocha/backgroundurl.txt");
  backgroundSha256 = builtins.readFile (./. + "../../../Themes/catppuccin-mocha/backgroundsha256.txt");
in
{
  imports = [ inputs.stylix.homeManagerModules.stylix ];

  stylix.enable = true;
  #stylix.polarity = themePolarity;
  #stylix.image = /home/cryptix/nix-dots/Modules/home-manager/style/city-horizon.jpg;
  #stylix.image = pkgs.fetchurl {
    #url = "https://raw.githubusercontent.com/orangci/walls-catppuccin-mocha/master/minimalist-black-hole.png";
    #sha256 = "wCXKHemZYxVYnWVwh6Ng/nGlUroRotXgvcOdSfqRPeo=";
  #};
  #stylix.base16Scheme = ./. + themePath;
  #stylix.targets.kitty.enable = true;
  #stylix.targets.gtk.enable = true;
  #stylix.targets.rofi.enable = true;
  home.packages = with pkgs; [
     
  ];

}



