{ ... }:
{
  networking.hostName = "carbon";
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.networkmanager.wifi.powersave = false;

  hardware.wirelessRegulatoryDatabase = true;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CA
    options iwlwifi power_save=0
  '';

  # Vite dev server + HMR websocket, so a USB-tethered phone can reach
  # `tauri android dev`.
  networking.firewall.allowedTCPPorts = [
    5173
    1421
  ];
}
