{ lib, runCommand }:

# The mobile PWA as a store directory holding exactly the files it needs:
# services.qubi.mobile publishes its root as-is, so it must never be a
# checkout.
runCommand "qubi-mobile"
  {
    src = lib.fileset.toSource {
      root = ../mobile;
      fileset = ../mobile;
    };
    meta.description = "Qubi mobile PWA (static files)";
  }
  ''
    mkdir -p $out
    cp -r $src/. $out/
  ''
