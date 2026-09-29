{ pkgs, ... }:
{
  # Hyprland + Quickshell. These are the pieces of GNOME the desktop still
  # relies on, declared explicitly instead of enabling GNOME wholesale.
  programs.hyprland.enable = true;

  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.libinput.enable = true;

  services.displayManager.defaultSession = "hyprland";
  # Off so the greeter is shown on boot; set enable = true to skip it.
  services.displayManager.autoLogin = {
    enable = false;
    user = "cryptix";
  };

  # gsettings backend for Stylix GTK theming and the prefer-dark autostart.
  programs.dconf.enable = true;
  # Mounts and trash for nautilus.
  services.gvfs.enable = true;
  services.gnome.gnome-keyring.enable = true;

  security.polkit.enable = true;
  # Without the setuid wrapper pkexec refuses to run, so Quickshell's polkit
  # agent (desktop/shell/modules/auth/) never receives a request.
  security.polkit.enablePkexecWrapper = true;

  # Read by the bar's battery module and the quick-settings power profiles.
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  # Hyprland's portal handles screencast; the GTK portal adds file choosers
  # and the dark-mode settings interface.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  environment.systemPackages = with pkgs; [
    nautilus
    glib # gsettings CLI
    gsettings-desktop-schemas
    xcursor-pro
    kanshi
    pavucontrol
    polkit_gnome
  ];
}
