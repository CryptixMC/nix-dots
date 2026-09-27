{ ... }:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # Keep the daemon out of the interactive-use way: a heavy Nix build should
  # never win a CPU/IO contention fight against the desktop session.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
  nixpkgs.config.allowUnfree = true;

  # Disk hygiene: this box has a documented history of running the disk to
  # near-zero during back-to-back nix+cargo build sessions. Let the daemon
  # auto-GC once free space drops below min-free, stopping once it has
  # reclaimed up to max-free, and periodically drop old system generations
  # so store paths they alone hold become collectible.
  nix.settings.min-free = 30 * 1024 * 1024 * 1024; # 30 GB
  nix.settings.max-free = 80 * 1024 * 1024 * 1024; # 80 GB

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-generations +5"; # keep last 5 for rollback safety
  };
}
