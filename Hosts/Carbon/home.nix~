{ config, pkgs, inputs, ... }:

{
  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";
  
  imports = [
    #inputs.nixvim.homeManagerModules.nixvim
  ];

  home.packages = [
    pkgs.cargo
    pkgs.rustc
    pkgs.rust-analyzer
    pkgs.nixd
    pkgs.gcc
    pkgs.bottom
    pkgs.eza
    pkgs.disfetch
    pkgs.fd
    pkgs.onefetch
    pkgs.prismlauncher
    pkgs.gfn-electron
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
        ls = "eza --icons -T -L=2";
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
        disfetch
        eval "$(direnv hook zsh)"  
      '';
    };

    #nixvim = {
      #enable = true;
      #options = {
        #number = true;
	#relativenumber = true;
	#shiftwidth = 2;
      #};
      #colorschemes.catppuccin.enable = true;
      #plugins.nvchad.enable = true;
    #};
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
}
