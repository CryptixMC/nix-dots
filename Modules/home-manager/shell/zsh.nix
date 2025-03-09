{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bottom
    bat
    fd
    eza
    onefetch
    disfetch
  ];
  programs.zsh = {
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
}
