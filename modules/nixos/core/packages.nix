{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    podman
    distrobox
    nh
    git
    pciutils
    iw
    wirelesstools
    foliate
    proton-vpn
    unzip
    direnv
    nix-direnv
    flameshot
    xwayland
    lazygit
    celeste
    onlyoffice-desktopeditors
    discord
    qbittorrent
    elephant
    claude-code
    claude-agent-acp
  ];
}
