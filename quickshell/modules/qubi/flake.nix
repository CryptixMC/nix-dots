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
        qubi-mobile = pkgs.callPackage ./nix/mobile.nix { };
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

        # Narrow on purpose: only the one class that has actually crashed a
        # live shell (a boolean `anchors {}` block on a non-Anchors
        # property) is an error. The other categories false-positive on
        # Quickshell's C++-backed singleton types.
        qmllint = pkgs.runCommand "qubi-qmllint" { } ''
          find ${./qml} -name '*.qml' -print0 | xargs -0 ${pkgs.qt6.qtdeclarative}/bin/qmllint \
            -I ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
            -I ${pkgs.quickshell}/lib/qt-6/qml \
            --unqualified disable \
            --uncreatable-type disable \
            --incompatible-type error \
            --unresolved-type disable
          touch $out
        '';

        # The QML tree must stay mountable anywhere: no import may reach
        # outside qml/ (a host shell's theme, a sibling module, ...).
        qml-self-contained = pkgs.runCommand "qubi-qml-self-contained" { } ''
          cd ${./qml}
          if grep -rnE '^import "(/|\.\./\.\.)' --include='*.qml' . \
             || grep -nE '^import "\.\.' ./*.qml; then
            echo "qml/ imports something outside its own tree" >&2
            exit 1
          fi
          touch $out
        '';

        # Nothing here may name a user, a uid or a checkout.
        no-host-paths = pkgs.runCommand "qubi-no-host-paths" { } ''
          cd ${./.}
          if grep -rnE '/home/[a-z]|/run/user/[0-9]|nix-dots' \
               --include='*.py' --include='*.qml' --include='*.html' --include='*.nix' \
               python/src qml mobile nix | grep -vE '^[^:]+:[0-9]+:\s*(#|//|example = )'; then
            echo "host-specific path in shipped code" >&2
            exit 1
          fi
          touch $out
        '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
