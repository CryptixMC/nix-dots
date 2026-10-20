{
  lib,
  fetchurl,
  buildFHSEnv,
}:
let
  pname = "ori";
  version = "0.15.7+d702b99";

  bin = fetchurl {
    url = "https://github.com/OpenRouterLabs/ori-releases/releases/download/cli-0.15.7-d702b99/ori-linux-x64";
    hash = "sha256-y8zbs+g4xF6lRVknWZZevU1ZL9zOz3sgFHPTb8MMx7U=";
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
    description = "OpenRouter CLI that runs coding agents against OpenRouter models";
    homepage = "https://openrouter.ai/ori";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
