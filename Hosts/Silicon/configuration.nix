{ config, pkgs, inputs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../Modules/nixos/apps/virtualization.nix
      ../../Modules/nixos/style/stylix.nix
      ../../Modules/nixos/apps/nvf.nix
      inputs.home-manager.nixosModules.default
    ];

  nixpkgs.overlays =
    [
      (final: prev: {
        dmraid = prev.dmraid.overrideAttrs (oA: {
	  patches = oA.patches ++ [
	    (prev.fetchpatch2 {
	      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/f298cd74e67a841289fd0f10ef4ee85cfbbc4133/pkgs/os-specific/linux/dmraid/fix-dmevent_tool.patch";
	      hash = "sha256-MmAzpdM3UNRdOk66CnBxVGgbJTzJK43E8EVBfuCFppc=";
	    })
	  ];
	});
      })
    ];


  boot.loader.grub.enable = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.useOSProber = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  services.displayManager.sddm.enable = true;
  services.xserver.enable = true;

  networking.hostName = "silicon";
  networking.networkmanager.enable = true;

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

  services.ollama = {
    enable = true;
    acceleration = "cuda";
  };

  programs.hyprland.enable = true;
  programs.zsh.enable = true;

  home-manager = {
    extraSpecialArgs = {inherit inputs;};
    users = {
      "cryptix" = import ./home.nix;
    };
  };

  services.printing.enable = true;

  services.devmon.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  systemd.tmpfiles.rules = [ "L+ /var/lib/qemu/firmware - - - - ${pkgs.qemu}/share/qemu/firmware" ];

  users.users.cryptix = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "dialout" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.zsh;
  };

  environment.systemPackages = with pkgs; [
    neovim
    swww
    waybar
    eww
    kitty
    firefox
    obs-studio
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
    lutris
    clang
    obsidian
    zed-editor
    pavucontrol
    nixd
    mpv
    xwayland
    nvtopPackages.full
    xfce.thunar
    inputs.rose-pine-hyprcursor.packages.${pkgs.system}.default
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  services.openssh.enable = true;

  system.stateVersion = "24.05"; # Did you read the comment?
}
