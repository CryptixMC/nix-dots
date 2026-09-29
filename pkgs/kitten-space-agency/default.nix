{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  dotnetCorePackages,
  icu,
  openssl,
  krb5,
  vulkan-loader,
  libglvnd,
  mesa,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxext,
  libxi,
  libxrandr,
  libxrender,
  libxinerama,
  libxfixes,
  libxdamage,
  libxcomposite,
  libxscrnsaver,
  libxxf86vm,
  libxtst,
  libdecor,
  alsa-lib,
  libpulseaudio,
}:
let
  pname = "kitten-space-agency";
  # The official download is behind a JS bot-check, so the tarball comes from
  # the community mirror the AUR package uses. Bump with update.sh.
  version = "2026.8.22.5348";
  buildNum = lib.last (lib.splitString "." version);
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://files.ksa-archive.net/builds/${buildNum}/ksa_linux_v${version}.tar.gz";
    hash = "sha256-oiqrmeP9bQyFjbulkzJhLnuanPGc0Wd2dks1lT/fS30=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # KSA dlopen()s nearly everything by bare soname, which autoPatchelf can't
  # rpath, so these also go on LD_LIBRARY_PATH in the wrapper. The .NET runtime
  # backs DOTNET_ROOT for hostfxr.
  buildInputs = [
    stdenv.cc.cc.lib
    icu
    openssl
    krb5
    vulkan-loader
    libglvnd
    mesa
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxext
    libxi
    libxrandr
    libxrender
    libxinerama
    libxfixes
    libxdamage
    libxcomposite
    libxscrnsaver
    libxxf86vm
    libxtst
    libdecor
    alsa-lib
    libpulseaudio
    dotnetCorePackages.runtime_10_0
  ];

  # Tarball layout varies between releases, so extract by hand.
  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;
  dontStrip = true; # prebuilt game binaries

  # Optional CoreCLR tracing lib; nixpkgs only ships .so.1 and it's unused.
  autoPatchelfIgnoreMissingDeps = [ "liblttng-ust.so.0" ];

  installPhase = ''
        runHook preInstall

        mkdir -p $out/opt/kitten-space-agency
        tar xf $src -C $out/opt/kitten-space-agency
        chmod +x $out/opt/kitten-space-agency/KSA $out/opt/kitten-space-agency/Brutal.Monitor.Subprocess

        mkdir -p $out/bin
        makeWrapper $out/opt/kitten-space-agency/KSA $out/bin/kitten-space-agency \
          --chdir $out/opt/kitten-space-agency \
          --set DOTNET_ROOT ${dotnetCorePackages.runtime_10_0}/share/dotnet \
          --add-flags -fixed-viewport \
          --prefix LD_LIBRARY_PATH : ${
            lib.makeLibraryPath [
              icu
              openssl
              krb5
              vulkan-loader
              libglvnd
              mesa
              wayland
              libxkbcommon
              libx11
              libxcursor
              libxext
              libxi
              libxrandr
              libxrender
              libxinerama
              libxfixes
              libxdamage
              libxcomposite
              libxscrnsaver
              libxxf86vm
              libxtst
              libdecor
              alsa-lib
              libpulseaudio
            ]
          }

        install -Dm444 ${./icon.png} $out/share/icons/hicolor/256x256/apps/kitten-space-agency.png

        mkdir -p $out/share/applications
        cat > $out/share/applications/kitten-space-agency.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Kitten Space Agency
    Comment=Experimental KSP successor
    Exec=$out/bin/kitten-space-agency
    Icon=kitten-space-agency
    Categories=Game;
    Terminal=false
    EOF

        # Second entry running under gamescope-egpu (modules/nixos/apps/games.nix).
        cat > $out/share/applications/kitten-space-agency-egpu.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Kitten Space Agency (eGPU)
    Comment=Experimental KSP successor, forced fullscreen on the eGPU via gamescope
    Exec=gamescope-egpu -- $out/bin/kitten-space-agency
    Icon=kitten-space-agency
    Categories=Game;
    Terminal=false
    EOF

        runHook postInstall
  '';

  passthru = {
    updateScript = ./update.sh;
  };

  meta = {
    description = "Kitten Space Agency — experimental Linux build (unofficial community mirror)";
    homepage = "https://ahwoo.com/store/KPbAA1Au/kitten-space-agency";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "kitten-space-agency";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
