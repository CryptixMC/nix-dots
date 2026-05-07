{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    prismlauncher
    #lutris
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };
}
