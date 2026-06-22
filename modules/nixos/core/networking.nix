{ ... }:
{
  networking.hostName = "carbon";
  networking.networkmanager.enable = true;
  networking.firewall.allowedUDPPorts = [
    53
    67
    68
  ];
}
