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

  # Vite dev server + HMR websocket, for testing Tauri Android apps on a
  # physical device tethered over USB (e.g. steady-app) — `tauri android dev`
  # binds Vite to the USB-tether interface IP (TAURI_DEV_HOST) so the phone
  # can load the page directly; without this the firewall silently drops
  # the phone's connection ("web page not available" in the WebView) even
  # though the server answers fine locally.
  networking.firewall.allowedTCPPorts = [ 5173 1421 ];
}
