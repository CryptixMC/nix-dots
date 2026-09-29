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
  # Off by default even with polkit.enable -- without this,
  # /run/current-system/sw/bin/pkexec resolves to the raw (non-setuid) nix
  # store binary, which refuses to run at all ("pkexec must be setuid
  # root", confirmed live: JobRunner.qml's privileged commands all failed
  # with exit 127 until this was set). Needed for Quickshell's own polkit
  # agent (modules/auth/PolkitAgentService.qml) to ever receive a request
  # in the first place -- pkexec is what actually asks polkit for
  # authorization.
  security.polkit.enablePkexecWrapper = true;

  # GNOME's desktopManager used to pull this in implicitly for its own
  # power applet; Quickshell's Battery.qml reads UPower.displayDevice
  # directly and needs the daemon running on the bus itself.
  services.upower.enable = true;

  # Quickshell's Quick Settings panel reads/writes
  # Quickshell.Services.UPower.PowerProfiles, which talks to this daemon
  # over D-Bus -- without it the profile toggle has nothing to bind to.
  services.power-profiles-daemon.enable = true;

  # Hyprland's own portal handles screencast/screenshot; the GTK portal
  # provides file choosers and the settings (dark-mode) interface.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  environment.systemPackages = with pkgs; [
    nautilus
    glib # gsettings CLI
    gsettings-desktop-schemas # org.gnome.desktop.interface schema
  ];
}
