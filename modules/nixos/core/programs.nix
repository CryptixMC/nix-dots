{ pkgs, ... }:
{
  programs.firefox.enable = true;
  programs.zsh.enable = true;
  # configuration.nix
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      curl
      libuuid
      libgcc
      icu
      vulkan-loader
      libGL
      wayland
      libxkbcommon
      xorg.libX11
      xorg.libXcursor
      xorg.libXi
      xorg.libXrandr
      libpulseaudio
    ];
  };
}
