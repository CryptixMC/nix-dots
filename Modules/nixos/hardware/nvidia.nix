{ config, ... }:
{
  hardware.graphics = {
    enable = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
    open = true;
  };

  hardware.graphics.enable32Bit = true;

  services.xserver.videoDrivers = [ "nvidia" ];
}
