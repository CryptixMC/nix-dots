{ config, pkgs, ... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";

  home.packages = [
    pkgs.cargo
    pkgs.rustc
    pkgs.gcc
    pkgs.bottom
    pkgs.eza
    pkgs.disfetch
    pkgs.fd
    pkgs.onefetch
  ];

  home.file = {

  };

  programs = {
    git = {
      enable = true;
      userName = "cryptix";
      userEmail = "cryptixmc@proton.me";
      aliases = {
        pu = "push";
        co = "checkout";
        cm = "commit";
      };
    };
  
    zsh = {
      enable = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      shellAliases = {
        ls = "eza --icons -l -T -L=2";
	cat = "bat";
	fd = "fd -Lu";
	fetch = "disfetch";
        gitfetch = "onefetch";
      };
      oh-my-zsh = {
        enable = true;
        plugins = [ "git" ];
        theme = "robbyrussell";
      };
      envExtra = ''
        fetch
        eval "$(direnv hook zsh)"  
      '';
    };
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
