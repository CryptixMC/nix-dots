{
  lib,
  fetchurl,
  buildFHSEnv,
}:
let
  pname = "proton-drive-cli";
  version = "0.4.6";

  bin = fetchurl {
    url = "https://proton.me/download/drive/cli/${version}/linux-x64/proton-drive";
    hash = "sha256-KiqzvqXE+Nm9o3EnrUWZyFw1wEdqNjppIldO4IdPJBE=";
    executable = true;
  };
in
# A Bun --compile binary: patchelf shifts the offset of its embedded bundle and
# breaks it, so run it unmodified in an FHS env.
buildFHSEnv {
  inherit pname version;

  targetPkgs = _pkgs: [ ];

  runScript = "${bin}";

  meta = {
    description = "Official command-line client for Proton Drive";
    homepage = "https://proton.me/drive";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
