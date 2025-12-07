{ ... }:
{
  imports = [
    ../../modules/home-manager/core/packages.nix
    ../../modules/home-manager/core/variables.nix
    ../../modules/home-manager/apps/ghostty.nix
    ../../modules/home-manager/wm/hyprland.nix
    ../../modules/home-manager/wm/waybar.nix
    ../../modules/home-manager/apps/zen-browser.nix
    ../../modules/home-manager/apps/zed.nix
    ../../modules/style/stylix.nix
    ../../modules/home-manager/core/portal.nix
  ];

  home.username = "cryptix";
  home.homeDirectory = "/home/cryptix";
  home.stateVersion = "25.05";

  nixpkgs.config = {
    allowUnfree = true; # Allow unfree packages like Cisco Packet Tracer
    permittedInsecurePackages = [
      "qtwebengine-5.15.19"
    ];
  };

  stylix.targets.zen-browser.enable = false;

  home.file = {

  };

  programs.home-manager.enable = true;
}
