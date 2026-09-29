{ pkgs, ... }:
{
  programs.firefox.enable = true;
  programs.zsh.enable = true;

  # adb needs no programs.adb: systemd >=258 grants uaccess via android-tools' udev rules.

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
      libx11
      libxcursor
      libxi
      libxrandr
      libpulseaudio
    ];
  };
}
