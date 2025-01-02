{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    stylix.url = "github:danth/stylix";
    nixvim = {
      url = "github:nix-community/nixvim";
       #If using a stable channel you can use `url = "github:nix-community/nixvim/nixos-<version>"`
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rose-pine-hyprcursor.url = "github:ndom91/rose-pine-hyprcursor";
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
	#inputs.nixvim.homeManagerModules.nixvim
	#stylix.nixosModules.stylix
      ];
    };
    silicon = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs system;};
      modules = [
        ./Hosts/Silicon/configuration.nix
	inputs.home-manager.nixosModules.default
	#inputs.nixvim.homeManagerModules.nixvim
      ];
    };
  };
  };
}
