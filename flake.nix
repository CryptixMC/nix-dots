{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      carbon = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = [
          ./Hosts/Carbon/configuration.nix
          inputs.home-manager.nixosModules.default
        ];
      };
      silicon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Use the 'path' function to ensure it's included correctly
          ./Hosts/Silicon/configuration.nix
        ];
      };
    };
  };
}
