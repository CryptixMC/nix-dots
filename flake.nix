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

    # Private repo, hence git+ssh. For local dev:
    # `--override-input qubi path:$HOME/Projects/qubi`.
    qubi.url = "git+ssh://git@github.com/CryptixMC/qubi";
    qubi.inputs.nixpkgs.follows = "nixpkgs";

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
      # The shape of the Qubi development VM. The guest system and the host
      # helpers both read these, so the ports cannot drift apart.
      qubiVm = {
        memorySize = 8192;
        cores = 4;
        sshPort = 2222;
        spicePort = 5900;
        vncPort = 5901;
        agentUser = "agent";
      };

      # Local packages, buildable standalone (`nix build .#kitten-space-agency`).
      packages.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfreePredicate =
              pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "kitten-space-agency"
                "proton-drive-cli"
              ];
          };
        in
        {
          kitten-space-agency = pkgs.callPackage ./pkgs/kitten-space-agency { };
          oneclient = pkgs.callPackage ./pkgs/oneclient { };
          ori = pkgs.callPackage ./pkgs/ori { };
          oneclient-new-cluster = pkgs.callPackage ./pkgs/oneclient-new-cluster { };
          proton-drive-cli = pkgs.callPackage ./pkgs/proton-drive-cli { };
          # Bootable Qubi dev VM (QEMU + SPICE + SSH forward + vsock).
          # Built from the same nixosConfigurations.qubi-vm the guest module
          # describes, so there is one source of truth.
          qubi-vm = self.nixosConfigurations.qubi-vm.config.system.build.vm;
          qubi-vm-cli = import ./lib/qubi-vm-cli.nix {
            inherit pkgs;
            vmRunner = "${self.packages.x86_64-linux.qubi-vm}/bin/run-nixos-vm";
            sshPort = self.qubiVm.sshPort;
            spicePort = self.qubiVm.spicePort;
            vncPort = self.qubiVm.vncPort;
            agentUser = self.qubiVm.agentUser;
          };
        };

      # The tree wrapper only hands .nix files to the formatter; the bare
      # binary chokes on the non-Nix files in this repository.
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;

      checks.x86_64-linux.qubi-boundary-guard = import ./lib/qubi-boundary-guard.nix {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        inherit (nixpkgs) lib;
        src = self;
      };

      nixosConfigurations = {
        # Qubi development VM guest. Single source of truth for the guest
        # system: the host-side module (modules/nixos/apps/qubi-vm.nix) builds
        # the bootable image from THIS configuration via vmVariant.
        qubi-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            nixpkgsPath = nixpkgs;
            qubiPkg = inputs.qubi.packages.x86_64-linux.default or inputs.qubi.packages.x86_64-linux.qubi-rust;
            qubiAppPkg =
              inputs.qubi.packages.x86_64-linux.qubi-app or inputs.qubi.packages.x86_64-linux.default;
            qubiAgentPkg = inputs.qubi.packages.x86_64-linux.qwen-code;
            agentSshKey = builtins.readFile ./keys/agent.pub;
            qubiVm = self.qubiVm;
          };
          modules = [
            ./modules/nixos/apps/qubi-vm-guest.nix
          ];
        };

        carbon = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            qubiVm = self.qubiVm;
            qubiVmPkg = self.packages.x86_64-linux.qubi-vm;
          };
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
