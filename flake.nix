{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    stylix.url = "github:danth/stylix";

    nvf.url = "github:notashelf/nvf";

    #hyprpanel.url = "github:Jas-SinghFSU/HyprPanel";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";

    rose-pine-hyprcursor.url = "github:ndom91/rose-pine-hyprcursor";
  };

  outputs = { self, nixpkgs, stylix, ... }@inputs:
  let
    system = "x86_x64-linux";
  in
  {
  nixosConfigurations = {
    carbon = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs system;};
      modules = [
        ./Hosts/Carbon/configuration.nix
        inputs.home-manager.nixosModules.default
        inputs.stylix.nixosModules.stylix
        inputs.nvf.nixosModules.default
      ];
    };
    silicon = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs system;};
      modules = [
        ./Hosts/Silicon/configuration.nix
        inputs.home-manager.nixosModules.default
        inputs.stylix.nixosModules.stylix
        inputs.nvf.nixosModules.default
      ];
    };
    hydrogen = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs system;};
      modules = [
        ./Hosts/Hydrogen/configuration.nix
        inputs.home-manager.nixosModules.default
        inputs.stylix.nixosModules.stylix
        inputs.nvf.nixosModules.default
      ];
    };
  };
  };
}
