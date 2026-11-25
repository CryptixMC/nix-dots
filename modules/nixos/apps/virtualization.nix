{ pkgs, ... }:
{
  virtualisation.docker.enable = true;

  programs.virt-manager.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Android container for game automation; binderfs is already in the kernel.
  virtualisation.waydroid.enable = true;

  environment.systemPackages = with pkgs; [
    docker
    lazydocker
    docker-compose
    scrcpy # on-demand view/control of the Waydroid or AVD display over adb
    uv # venv for uiautomator2 / adbutils / opencv scripts
  ];

  # Qubi development VM (QEMU + SPICE + SSH + vsock)
  imports = [ ./qubi-vm.nix ];
}
