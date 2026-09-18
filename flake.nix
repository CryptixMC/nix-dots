{
  description = "My NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned separately from the main nixpkgs input SOLELY to get a known-
    # good quickshell build. The main input's quickshell 0.3.1 ships with
    # NO compiled QML plugin at all (lib/qt-6/qml/Quickshell/ has qmldir +
    # qmltypes but zero .so files anywhere in the whole package -- confirmed
    # live via QT_DEBUG_PLUGINS=1 tracing: `resolvePlugin Could not resolve
    # dynamic plugin with base name "quickshell-coreplugin"... file does
    # not exist`, in both the embedded-resource and filesystem search
    # paths, on a genuinely fresh build, not a stale/corrupted local one).
    # NixHub's own version index doesn't even have 0.3.1 yet -- 0.3.0 (this
    # commit) is the latest indexed, presumably-working version. This
    # input exists ONLY to overlay `quickshell` back to that commit;
    # `follows` isn't used here on purpose, since the whole point is a
    # DIFFERENT nixpkgs snapshot than the main one.
    nixpkgs-quickshell-pin.url = "github:NixOS/nixpkgs/c27cdad491a991b11ed731760aa2ef8db0cb0410";

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
      nixpkgs-quickshell-pin,
      home-manager,
      stylix,
      claude-desktop,
      ...
    }@inputs:
    let
      # Single overlay definition shared by both nixosConfigurations.carbon
      # (via nixpkgs.overlays) and homeConfigurations.cryptix (via a
      # manually-imported pkgs below) -- quickshell is referenced from
      # both sides (modules/nixos/core/packages.nix + services/greetd.nix
      # on the NixOS side; modules/home-manager/apps/goose.nix's qmllint
      # -I include path on the home-manager side), so both need the same
      # override or qml-lint-repo would validate against a different
      # quickshell version than what's actually installed.
      quickshellPinOverlay = final: prev: {
        quickshell = nixpkgs-quickshell-pin.legacyPackages.${prev.system}.quickshell;
      };
    in
    {
      nixosConfigurations = {
        carbon = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.overlays = [ quickshellPinOverlay ]; }
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
            overlays = [ quickshellPinOverlay ];
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
