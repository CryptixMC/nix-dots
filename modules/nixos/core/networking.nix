{ ... }:
{
  networking.hostName = "carbon";
  networking.networkmanager.enable = true;

  hardware.wirelessRegulatoryDatabase = true;
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=0
  '';
}
