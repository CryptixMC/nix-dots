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
    xwayland
    lazygit
    onlyoffice-desktopeditors
    discord
    qbittorrent
    (pkgs.callPackage ../../../pkgs/oneclient { })
    (pkgs.callPackage ../../../pkgs/oneclient-new-cluster { })
    android-tools # adb/fastboot; udev rules give USB-debugging access
    claude-code
    claude-agent-acp
    hyprshot # region/window/output screenshots, piped to satty (binds in wm/hyprland.nix)
    satty
    wl-clipboard
    quickshell # the desktop shell — config lives in quickshell/
    yq-go # base16.yaml -> JSON for quickshell/theme/ThemeLoader.qml
    adwaita-icon-theme # named-icon lookups fall back to blanks without a real icon theme
    ghostty
    zenith
    fzf
    eza
    fd
    bat
    bottom
    onefetch
  ];
}
