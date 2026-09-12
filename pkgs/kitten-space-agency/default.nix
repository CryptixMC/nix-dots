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
  # Upstream (Ahwoo) gates its own download page behind a JS bot-check, so
  # there's no scrapable "latest" URL on the official site itself. update.sh
  # instead queries RocketWerkz's own version-check API (the same one the
  # game hits on every launch — see logs/KittenSpaceAgency.log) for the
  # version number, falling back to the AUR kittenspaceagency-bin package's
  # manually-maintained Version if that's ever unreachable. Either way the
  # actual tarball is fetched from files.ksa-archive.net — the community
  # mirror AUR's PKGBUILD also sources from, since RocketWerkz's API only
  # links to the JS-gated download page, not a raw file.
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

  # KSA is a native Vulkan engine that dlopen()s essentially everything at
  # runtime (windowing backend, Vulkan, audio, and even .NET's own ICU
  # shim) by bare soname rather than linking it — confirmed via ldd (only
  # libc/libstdc++/libgcc show as real NEEDED entries anywhere) and
  # strings (things like libvulkan.so.1, libwayland-client.so.0,
  # libasound.so.2, libicuuc.so are string literals, not linker deps).
  # autoPatchelfHook only rpaths what it sees as a real NEEDED entry, so
  # it can't fix bare dlopen() calls — these libraries are instead put on
  # LD_LIBRARY_PATH via the wrapper below, same role nix-ld plays
  # system-wide. dotnetCorePackages.runtime_10_0 backs DOTNET_ROOT so
  # hostfxr resolution works, matching the AUR package's declared dep.
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

  # Upstream tarball layout isn't stable across releases — older builds
  # nest everything under linux-x64/, this one (2026.8.22.5348) has
  # Content/, KSA, etc. at the tarball root — so stdenv's single-top-dir
  # auto-unpack can't be relied on. Extract by hand instead.
  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;
  dontStrip = true; # matches AUR's options=(!strip) — game ships prebuilt, unrelated shared libs

  # CoreCLR's optional ETW/LTTng tracing provider wants liblttng-ust.so.0
  # (an old ABI — nixpkgs' current lttng-ust only ships .so.1). Tracing is
  # off by default and CoreCLR runs fine without it; skip rather than
  # chase a soname nixpkgs doesn't build anymore.
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

    # Second launcher entry that runs the game inside gamescope-egpu (see
    # modules/nixos/apps/games.nix) — forces real fullscreen at the
    # eGPU-attached output's native resolution instead of relying on
    # Hyprland's global MESA_VK_DEVICE_SELECT/DRI_PRIME env vars alone to
    # steer device selection.
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
