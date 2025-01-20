{ pkgs,... }:

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
    pkgs.prusa-slicer
    pkgs.hyprpaper
  ];

  home.file = {

  };

  programs = {
    kitty.enable = true;
    #waybar.enable = true;
    wofi.enable = true;

    #hyprland = {
      #enable = true;
    #};

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
