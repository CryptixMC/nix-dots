{ ... }:
{
  services.openssh.enable = true;
  services.tailscale.enable = true;
  services.printing.enable = true;
  services.flatpak.enable = true;

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # No disk swap on this machine; compressed RAM swap absorbs memory spikes
  # (a large local model plus a heavy build) without wearing the NVMe.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
}
