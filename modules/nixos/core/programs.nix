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
    ];
  };
}
