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
}
