{ ... }:
{
  # Disabled in favor of greetd + ReGreet — see modules/nixos/services/greetd.nix.
  # Flip back to true to revert.
  services.displayManager.gdm.enable = false;
  services.desktopManager.gnome.enable = true;
}
