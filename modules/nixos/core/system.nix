{ pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/Winnipeg";
  i18n.defaultLocale = "en_CA.UTF-8";

  users.users.cryptix = {
    isNormalUser = true;
    description = "cryptix";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "render"
      "video"
    ];
    shell = pkgs.zsh;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  # A heavy build should never win CPU/IO contention against the desktop.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
  nixpkgs.config.allowUnfree = true;

  # GC during builds when free space runs low.
  nix.settings.min-free = 30 * 1024 * 1024 * 1024; # 30 GB
  nix.settings.max-free = 80 * 1024 * 1024 * 1024; # 80 GB

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-generations +5";
  };
}
