{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    podman
    distrobox
    nh
    git
    pciutils
    foliate
    cudaPackages.cudatoolkit
    protonvpn-gui
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
  ];
}
