{ pkgs, ... }:
{
  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.opengl = {
    enable = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      mesa
      mesa.drivers
      vulkan-loader
      vulkan-validation-layers
    ];
  };
}
