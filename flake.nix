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

    # Qubi is its own repo now (github.com/CryptixMC/qubi), installable from
    # its own flake alone -- this repo only imports it and sets host values.
    # It ships its QML as a real `Qubi` module and its home-manager module
    # puts that on QML_IMPORT_PATH, so nothing here names a checkout path.
    # For live-editable development set programs.qubi.devCheckout (QML hot
    # reload) and/or pass `--override-input qubi path:$HOME/Projects/qubi`
    # (engine); see that repo's README. Still private, hence git+ssh instead
    # of github:; switch to `github:CryptixMC/qubi` when it goes public.
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

      # Boundary guard (Qubi master plan, Phase 1): after the Qubi split this
      # repo is only supposed to IMPORT the Qubi flake and set host values.
      # This check fails the build the moment any *.nix/*.qml file outside
      # the allowlist below starts mentioning Qubi -- i.e. the moment new
      # Qubi-specific logic creeps back into nix-dots instead of living in
      # the qubi repo. Scoped to *.nix/*.qml (the executable configuration
      # surface) rather than every text file, so that docs/history/*,
      # README.md, TODO.md, .mcp.json and theme *.json token files (data,
      # not code -- and already covered by the qml side of the allowlist
      # below) don't trip it; those are free to discuss Qubi.
      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          # The complete, enumerated Qubi surface in nix-dots. Read this list
          # to see everywhere this repo still touches Qubi.
          #
          #   (a) stable integration points: expected to remain indefinitely
          #       (the flake input, the two module imports + `services.qubi`
          #       block, the two amd.nix eGPU hook calls, the Hyprland IPC
          #       keybind comments, and the quickshell `Qubi`/`QubiStatus`
          #       QML modules + theme-token passthrough).
          #   (d) transitional: these still legitimately configure Qubi today
          #       (the qubi-state-sync coupling, now in qubi-hwstate.nix since
          #       Phase 5 Step 10 removed goose.nix) but are expected to
          #       SHRINK and eventually disappear as later phases delete/
          #       replace claude-usage.nix and ai-workstation.nix's
          #       qubi-state-sync call. Tolerated now, not invisible --
          #       re-check this list each phase.
          #   (b) known stale comments (name files that no longer exist,
          #       e.g. a bygone qubi-health.nix) living in files outside
          #       this check's ownership; allowlisted so the guard can still
          #       run today, flagged here as cleanup debt for their owners.
          qubiAllowlist = [
            # -- (a) stable --
            "flake.nix"
            "hosts/carbon/configuration.nix"
            "hosts/carbon/home.nix"
            "modules/home-manager/apps/qubi.nix"
            "modules/home-manager/wm/hyprland.nix"
            "modules/nixos/hardware/amd.nix"
            "quickshell/shell.qml"
            "quickshell/theme/Theme.qml"
            "quickshell/theme/ThemeDefaults.qml"
            "quickshell/modules/bar/QubiStatus.qml"
            "quickshell/modules/bar/RightModules.qml"
            # -- (d) transitional, expected to shrink --
            "modules/home-manager/apps/qubi-hwstate.nix"
            "modules/home-manager/apps/claude-usage.nix"
            "modules/nixos/apps/ai-workstation.nix"
            "lib/mkUserScript.nix"
            # -- (b) stale comment, not this check's file to fix --
            "lib/scriptWithPath.nix"
          ];
          allowRegex = "^(" + builtins.concatStringsSep "|" (map (p: nixpkgs.lib.escapeRegex p) qubiAllowlist) + ")$";
        in
        {
          qubi-boundary-guard = pkgs.runCommand "qubi-boundary-guard" { } ''
            cd ${self}
            fail=0
            while IFS= read -r -d $'\0' f; do
              rel=''${f#./}
              if grep -qiI 'qubi' "$f"; then
                if ! printf '%s' "$rel" | grep -qE '${allowRegex}'; then
                  echo "qubi-boundary-guard: $rel mentions qubi but is not in the flake.nix allowlist" >&2
                  fail=1
                fi
              fi
            done < <(find . \( -name '*.nix' -o -name '*.qml' \) -print0)
            if [ "$fail" -ne 0 ]; then
              exit 1
            fi
            touch $out
          '';
        };

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
