{
  description = "Qubi: a multi-tier local-first assistant in front of goose";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        qubi = pkgs.callPackage ./nix/package.nix { };
        default = qubi;
      });

      overlays.default = final: _prev: {
        qubi = final.callPackage ./nix/package.nix { };
      };

      # `imports = [ inputs.qubi.homeModules.qubi ];` then see
      # nix/hm-module.nix for programs.qubi.* / services.qubi.*.
      homeModules.qubi = ./nix/hm-module.nix;
      homeModules.default = self.homeModules.qubi;

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (
              p: with p; [
                websockets
                pyyaml
                pytest
                ruff
              ]
            ))
            pkgs.sqlite
          ];
          shellHook = ''export PYTHONPATH="$PWD/python/src''${PYTHONPATH:+:$PYTHONPATH}"'';
        };
      });

      checks = forAllSystems (pkgs: {
        # buildPythonApplication runs the pytest suite in its checkPhase.
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.qubi;

        ruff = pkgs.runCommand "qubi-ruff" { nativeBuildInputs = [ pkgs.ruff ]; } ''
          cd ${./.}
          ruff check --no-cache .
          touch $out
        '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
