{ ... }:
{
  services.xserver.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Off while testing greetd + ReGreet, so the greeter is actually seen on boot.
  # Flip enable back to true to revert.
  services.displayManager.autoLogin = {
    enable = false;
    user = "cryptix";
  };

  services.displayManager.defaultSession = "hyprland";
}
