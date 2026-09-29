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
    cliphist # clipboard history, piped from wl-paste (watch hook in home-manager/wm/hyprland.nix)
    hyprpicker # colour picker, bound in wm/hyprland.nix
    quickshell # the desktop shell (desktop/shell/)
    yq-go # base16.yaml -> JSON for desktop/shell/theme/ThemeLoader.qml
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
