# Thin wrapper around pkgs.writeShellScript that dedupes the repeated
# `PATH=${lib.makeBinPath [ ... ]}:$PATH` preamble. Matches
# pkgs.writeShellScript's semantics exactly (no forced `set -e`, no
# shellcheck) -- deliberately NOT pkgs.writeShellApplication, since several
# existing scripts rely on `set -uo pipefail` (no -e) to keep going past
# commands that are expected to "fail" (grep with no match, etc.), and
# writeShellApplication's shellcheck pass hasn't been run against this
# repo's scripts.
#
# Only fits pkgs.writeShellScript call sites (bare scripts). Sites using
# pkgs.writeShellScriptBin (a derivation with $out/bin/<name>, e.g.
# qubi-health.nix's healthCli) are a different builder and stay as-is.
{ lib, pkgs }:
{
  name,
  runtimeInputs,
  text,
}:
pkgs.writeShellScript name ''
  PATH=${lib.makeBinPath runtimeInputs}:$PATH
  ${text}
''
