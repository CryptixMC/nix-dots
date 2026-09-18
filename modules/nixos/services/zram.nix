{ ... }:
{
  # No swap exists today on this 38GB-RAM/no-swap laptop — a memory-pressure
  # spike (a large local model plus a heavy build) has nowhere to go but OOM.
  # zram gives compressed RAM-backed swap instead of a disk-backed swapfile,
  # so it costs no disk space and doesn't wear the NVMe.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };
}
