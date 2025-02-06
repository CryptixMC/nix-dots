{ pkgs, inputs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../Modules/nixos/apps/virtualization.nix
      ../../Modules/nixos/style/stylix.nix
      ../../Modules/nixos/apps/nvf.nix
      ../../Modules/nixos/wm/hyprland.nix
      ../../Modules/nixos/hardware/amd.nix
      inputs.home-manager.nixosModules.default
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.displayManager.ly.enable = true;
  services.xserver.enable = true;

  networking.hostName = "carbon";

  networking.networkmanager.enable = true;
  
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "America/Central";

  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
  
  #programs.hyprland.enable = true;

  programs.zsh.enable = true;

  home-manager = {
    backupFileExtension = "backup";
    extraSpecialArgs = {inherit inputs;};
    users = {
      "cryptix" = import ./home.nix;
    };
  };

  services.printing.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  systemd.tmpfiles.rules = [ "L+ /var/lib/qemu/firmware - - - - ${pkgs.qemu}/share/qemu/firmware" ];

  services.libinput.enable = true;

  users.users.cryptix = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "dialout" ];
    shell = pkgs.zsh;
  };

  environment.systemPackages = with pkgs; [
    neovim
    swww
    waybar
    eww
    kitty
    wofi
    firefox
    dunst
    qemu
    direnv
    nix-direnv
    brightnessctl
    dolphin
    yazi
    git
    bat
    nh
    home-manager
    hyprpaper
    lutris
    clang
    prusa-slicer
    zed-editor
    arduino
    xfce.thunar
    inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  services.openssh.enable = true;

  system.stateVersion = "24.05";

}
