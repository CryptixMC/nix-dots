# pkgs.writeShellScript with a PATH preamble. Not writeShellApplication: some
# scripts rely on running without `set -e` and haven't been shellchecked.
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
