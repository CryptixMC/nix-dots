{ ... }:
{
  networking.hostName = "carbon";
  networking.networkmanager.enable = true;
  # Intel CNVi WiFi (Alder Lake) drops association under power save — disable it
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = "options iwlwifi power_save=0";
  networking.firewall.allowedUDPPorts = [
    53
    67
    68
  ];
}
