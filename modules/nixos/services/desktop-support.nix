{ pkgs, ... }:
{
  # The desktop is Hyprland + Quickshell. GNOME's desktopManager used to be
  # enabled wholesale just for these support pieces; they're declared
  # explicitly now and the rest of GNOME is gone.

  # gsettings backend — stylix gtk theming and the autostart
  # `gsettings set ... prefer-dark` (see home-manager wm/hyprland.nix).
  programs.dconf.enable = true;

  # Mounts/trash for nautilus (pulls in udisks2).
  services.gvfs.enable = true;

  # Secret storage; D-Bus activated. seahorse (home packages) manages it.
  services.gnome.gnome-keyring.enable = true;

  security.polkit.enable = true;

  # GNOME's desktopManager used to pull this in implicitly for its own
  # power applet; Quickshell's Battery.qml reads UPower.displayDevice
  # directly and needs the daemon running on the bus itself.
  services.upower.enable = true;

  # Hyprland's own portal handles screencast/screenshot; the GTK portal
  # provides file choosers and the settings (dark-mode) interface.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  environment.systemPackages = with pkgs; [
    nautilus
    glib # gsettings CLI
    gsettings-desktop-schemas # org.gnome.desktop.interface schema
  ];
}
