{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gimp
    gimpPlugins.gmic
    gimp-with-plugins
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
    telegram-desktop
    whatsapp-electron
    mangohud
  ];
}
