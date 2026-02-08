{
  config,
  lib,
  pkgs,
  ...
}:
{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.open = true;
  hardware.nvidia.modesetting.enable = true;
  hardware.nvidia.powerManagement.enable = false;
  hardware.nvidia.nvidiaSettings = true;
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;

  # Ensure nvidia-drm modesetting is enabled early (needed for external GPUs / eGPUs)
  boot.kernelParams = lib.mkDefault [ "nvidia-drm.modeset=1" ];
  boot.initrd.kernelModules = lib.mkDefault [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];
  boot.kernelModules = lib.mkDefault [
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
  ];

  # Enable bolt daemon so Thunderbolt devices can be authorized (boltd).
  systemd.services.bolt = {
    description = "Thunderbolt device daemon (bolt)";
    wants = [ "dbus.service" ];
    after = [ "dbus.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.bolt}/libexec/boltd";
      Restart = "on-failure";
      RestartSec = 5;
      KillMode = "process";
    };
    wantedBy = [ "multi-user.target" ];
    enable = true;
  };

  services.xserver.enable = true;
}
