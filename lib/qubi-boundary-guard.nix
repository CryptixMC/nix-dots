# Fails if any .nix/.qml file outside the allowlist mentions Qubi. Qubi lives
# in its own repo; this one should only import it and set host values.
{
  pkgs,
  lib,
  src,
}:
let
  allowlist = [
    # Integration points
    "flake.nix"
    "lib/qubi-boundary-guard.nix"
    "hosts/carbon/configuration.nix"
    "hosts/carbon/home.nix"
    "modules/home-manager/apps/qubi.nix"
    "modules/home-manager/wm/hyprland.nix"
    "modules/nixos/hardware/amd.nix"
    "desktop/shell/shell.qml"
    "desktop/shell/theme/Theme.qml"
    "desktop/shell/theme/ThemeDefaults.qml"
    "desktop/shell/modules/bar/QubiStatus.qml"
    "desktop/shell/modules/bar/QubiGlyph.qml"
    "desktop/shell/modules/bar/RightModules.qml"
    # Transitional: expected to move into Qubi over time
    "modules/home-manager/apps/qubi-hwstate.nix"
    "modules/home-manager/apps/claude-usage.nix"
    "modules/nixos/apps/ai-workstation.nix"
    "lib/mkUserScript.nix"
    "lib/scriptWithPath.nix"
    "desktop/shell/modules/bar/BarIcon.qml"
  ];
  allowRegex = "^(" + lib.concatMapStringsSep "|" lib.escapeRegex allowlist + ")$";
in
pkgs.runCommand "qubi-boundary-guard" { } ''
  cd ${src}
  fail=0
  while IFS= read -r -d $'\0' f; do
    rel=''${f#./}
    if grep -qiI 'qubi' "$f" && ! printf '%s' "$rel" | grep -qE '${allowRegex}'; then
      echo "qubi-boundary-guard: $rel mentions qubi but is not in lib/qubi-boundary-guard.nix's allowlist" >&2
      fail=1
    fi
  done < <(find . \( -name '*.nix' -o -name '*.qml' \) -print0)
  [ "$fail" -eq 0 ] && touch $out
''
