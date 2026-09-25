{
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../modules/nixos/core/bootloader.nix
    ../../modules/nixos/core/networking.nix
    ../../modules/nixos/core/locale.nix
    ../../modules/nixos/core/users.nix
    ../../modules/nixos/core/nix.nix
    ../../modules/nixos/core/packages.nix
    ../../modules/nixos/core/programs.nix

    ../../modules/nixos/hardware/amd.nix
    ../../modules/nixos/hardware/thinkpad-power.nix

    ../../modules/nixos/services/pipewire.nix
    ../../modules/nixos/services/printing.nix
    ../../modules/nixos/services/ssh.nix
    ../../modules/nixos/services/tailscale.nix
    ../../modules/nixos/services/xserver.nix
    ../../modules/nixos/services/greetd.nix
    ../../modules/nixos/services/fprintd.nix
    ../../modules/nixos/services/quickshell-lock.nix
    ../../modules/nixos/services/libinput.nix
    ../../modules/nixos/services/flatpak.nix
    ../../modules/nixos/services/desktop-support.nix
    ../../modules/nixos/services/zram.nix
    ../../modules/nixos/services/bluetooth.nix

    ../../modules/nixos/apps/games.nix
    ../../modules/nixos/apps/virtualization.nix
    ../../modules/nixos/apps/docker.nix
    ../../modules/nixos/apps/ai-workstation.nix

    ../../modules/nixos/wm/hyprland.nix

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

  # Guarantee Magic SysRq (e.g. REISUB) works as a last-resort recovery
  # path if the eGPU wedges the session and SSH/Tailscale is unreachable.
  boot.kernel.sysctl."kernel.sysrq" = 1;
}
