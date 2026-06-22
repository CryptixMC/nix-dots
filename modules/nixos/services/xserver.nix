{ ... }:
{
  services.xserver.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = "cryptix";
  };

  services.displayManager.defaultSession = "hyprland";
}
