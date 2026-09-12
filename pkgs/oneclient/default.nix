{
  lib,
  fetchurl,
  appimageTools,
}:
let
  pname = "oneclient";
  version = "2.0.1";

  src = fetchurl {
    url = "https://github.com/Polyfrost/OneLauncher/releases/download/oneclient-${version}/OneClient_${version}_linux_x86_64.AppImage";
    hash = "sha256-HMEeoC34uDcU65U6IKOuuos0G5NeTRD07Otjb9KiCyQ=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/oneclient_app.desktop $out/share/applications/oneclient_app.desktop
    install -m 444 -D ${appimageContents}/oneclient_app.png $out/share/icons/hicolor/128x128/apps/oneclient_app.png
    substituteInPlace $out/share/applications/oneclient_app.desktop \
      --replace-fail 'Exec=oneclient_app' 'Exec=${pname}'
  '';

  meta = {
    description = "Next-generation open source Minecraft launcher by Polyfrost";
    homepage = "https://polyfrost.org/projects/oneclient";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
