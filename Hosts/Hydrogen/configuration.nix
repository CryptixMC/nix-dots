{ pkgs, inputs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../Modules/nixos/hardware/nvidia.nix
      ../../Modules/nixos/wm/hyprland.nix
      ../../Modules/nixos/style/stylix.nix
      ../../Modules/nixos/apps/virtualization.nix
      ../../Modules/nixos/apps/nvf.nix
      inputs.home-manager.nixosModules.default
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hydrogen";

  home-manager = {
    backupFileExtension = "bak";
    extraSpecialArgs = {inherit inputs;};
    users = {
      "cryptix" = import ./home.nix;
    };
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking.networkmanager.enable = true;

  time.timeZone = "America/Winnipeg";

  i18n.defaultLocale = "en_CA.UTF-8";

  services.xserver.enable = true;

  services.displayManager.ly.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  users.users.cryptix = {
    isNormalUser = true;
    description = "cryptix";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "dialout" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  programs.firefox.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    neovim
    zed-editor
    nh
    home-manager
    nvtop
  ];

  services.openssh.enable = true;

  system.stateVersion = "24.11";
}
