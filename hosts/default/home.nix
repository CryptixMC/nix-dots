{ config, pkgs, ... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";

  home.stateVersion = "24.05"; # Please read the comment before changing.

  home.packages = [

  ];

  home.file = {

  };

  home.sessionVariables = {
    EDITOR = "zeditor";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
