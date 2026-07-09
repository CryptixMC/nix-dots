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
    proton-pass
    proton-authenticator
    protonmail-bridge-gui
    protonmail-desktop
    (pkgs.callPackage ../../../pkgs/proton-drive-cli { })
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
