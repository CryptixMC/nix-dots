{ pkgs, ... }:
{
  programs.firefox.enable = true;
  programs.zsh.enable = true;

  # USB debugging (adb/fastboot) for Android dev — e.g. Tauri Android builds.
  # `programs.adb` was removed: systemd >=258 grants uaccess to adb/fastboot
  # devices automatically once android-tools' udev rules are present, so no
  # group/adbusers dance is needed — just the package (see packages.nix).

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
      libx11
      libxcursor
      libxi
      libxrandr
      libpulseaudio
    ];
  };
}
