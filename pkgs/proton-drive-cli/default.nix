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
# Bun `--compile` executables append their bundle as raw trailing data past a
# fixed offset; autoPatchelf rewrites the ELF header and shifts that offset,
# corrupting the embedded app (verified: patched binary silently falls back
# to bare `bun`'s own CLI). Run the untouched binary in an FHS env instead.
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
