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
    # celeste: broken on rustc 1.97+ (rustix 0.37.27 uses removed internal
    # rustc_attrs, still unfixed on nixos-unstable) - re-add once fixed upstream
    onlyoffice-desktopeditors
    discord
    qbittorrent
    (pkgs.callPackage ../../../pkgs/oneclient { })
    (pkgs.callPackage ../../../pkgs/oneclient-new-cluster { })
    android-tools # adb/fastboot udev rules — USB debugging for Android dev
    # elephant # Walker's backend daemon, hidden alongside Walker itself —
    # see TODO.md §3; re-add if Walker is ever restored.
    claude-code
    claude-agent-acp
    # Screenshotting: hyprshot wraps grim+slurp+hyprpicker for region/window/
    # output capture; satty is the wlroots-native annotate/save/copy UI. See
    # binds in modules/home-manager/wm/hyprland.nix.
    hyprshot
    satty
    wl-clipboard
    quickshell # desktop shell toolkit — quickshell/ scaffold, see TODO.md §3
    yq-go # YAML->JSON bridge for quickshell/theme/ThemeLoader.qml (base16.yaml has no native QML parser)
  ];
}
