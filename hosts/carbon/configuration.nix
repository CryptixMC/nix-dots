{
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../modules/nixos/core/system.nix
    ../../modules/nixos/core/networking.nix
    ../../modules/nixos/core/packages.nix
    ../../modules/nixos/core/programs.nix

    ../../modules/nixos/hardware/amd.nix
    ../../modules/nixos/hardware/thinkpad-power.nix

    ../../modules/nixos/services/common.nix
    ../../modules/nixos/services/desktop.nix
    ../../modules/nixos/services/pipewire.nix
    ../../modules/nixos/services/greetd.nix
    ../../modules/nixos/services/fprintd.nix
    ../../modules/nixos/services/quickshell-lock.nix

    ../../modules/nixos/apps/games.nix
    ../../modules/nixos/apps/virtualization.nix
    ../../modules/nixos/apps/ai-workstation.nix

    ../../modules/style/stylix.nix

    inputs.qubi.nixosModules.qubi
  ];

  programs.claude-desktop.enable = true;

  system.stateVersion = "25.11";

  services.qubi = {
    user = "cryptix";
    egpu = {
      enable = true;
      gpuDeviceId = "1002:73bf";
      pciSlot.outer = "0000:50:00.0";
      pciSlot.inner = "0000:51:01.0";
      thunderboltUniqueId = "b9010000-0062-640e-83f2-8ddd4a93f908";
    };
    gpu.userControl = true;
    gaming.cpuRange = "8-15";
    searxng = {
      enable = true;
      secretKeyFile = "/etc/qubi/searxng.env";
    };
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  # Magic SysRq as last-resort recovery if the eGPU wedges the session.
  boot.kernel.sysctl."kernel.sysrq" = 1;
}
