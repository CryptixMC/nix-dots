{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    #stylix.url = "github:danth/stylix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: 
  let 
    system = "x86_x64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
  in
  {
  nixosConfigurations = {
    carbon = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs system;};
      modules = [
        ./Hosts/Carbon/configuration.nix
        inputs.home-manager.nixosModules.default
	#stylix.nixosModules.stylix
      ];
    };
    silicon = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./Hosts/Silicon/configuration.nix
      ];
    };
  };
  };
}
