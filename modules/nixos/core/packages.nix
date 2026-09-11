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
    # elephant # Walker's backend daemon, hidden alongside Walker itself —
    # see TODO.md §3; re-add if Walker is ever restored.
    claude-code
    claude-agent-acp
    quickshell # desktop shell toolkit — quickshell/ scaffold, see TODO.md §3
  ];
}
