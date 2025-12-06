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
      rconvert = "~/Scripts/resolve_convert.sh";
    };
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "direnv"
      ];
      theme = "robbyrussell";
    };
    envExtra = ''
      eval "$(direnv hook zsh)"
    '';
  };
}
