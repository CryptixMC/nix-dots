{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    ghostty
    #zen-browser
    zenith
    zenith-nvidia
    fzf
    eza
    fd
    bat
    bottom
    onefetch
  ];
}
