{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    # The RX 6800 XT eGPU is hotplugged over Thunderbolt and isn't reliably
    # present when ollama.service starts at boot, so it may come up CPU-only.
    # egpu-bar-fix.service (modules/nixos/hardware/amd.nix) restarts ollama
    # once the GPU's PCIe BAR is fixed up and the amdgpu driver is bound,
    # so it picks up ROCm shortly after the eGPU is plugged in.
    package = pkgs.ollama-rocm;
  };
}
