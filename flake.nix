{
  description = "My NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix.url = "github:danth/stylix";

    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.inputs.home-manager.follows = "home-manager";

    claude-desktop.url = "github:poeck/claude-desktop-nix-flake";
    claude-desktop.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      stylix,
      claude-desktop,
      ...
    }@inputs:
    {
      # The local packages, buildable on their own (`nix build
      # .#kitten-space-agency`) instead of only as part of a full system
      # rebuild. kitten-space-agency (unfree) and oneclient are nixpkgs
      # candidates; proton-drive-cli is a binary-only blob and stays here.
      packages.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
              "kitten-space-agency"
              "proton-drive-cli"
            ];
          };
        in
        {
          kitten-space-agency = pkgs.callPackage ./pkgs/kitten-space-agency { };
          oneclient = pkgs.callPackage ./pkgs/oneclient { };
          oneclient-new-cluster = pkgs.callPackage ./pkgs/oneclient-new-cluster { };
          proton-drive-cli = pkgs.callPackage ./pkgs/proton-drive-cli { };
        };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;

      nixosConfigurations = {
        carbon = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/carbon/configuration.nix
            stylix.nixosModules.stylix
            claude-desktop.nixosModules.claude-desktop
          ];
        };
      };
      homeConfigurations = {
        cryptix = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            system = "x86_64-linux";
          };
          modules = [
            ./hosts/carbon/home.nix
            stylix.homeModules.stylix
          ];
          extraSpecialArgs = { inherit inputs; };
        };
      };
    };
}
