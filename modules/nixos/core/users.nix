{ pkgs, ... }:
{
  users.users.cryptix = {
    isNormalUser = true;
    description = "cryptix";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
      "render"
      "video"
    ];
    shell = pkgs.zsh;
  };
}
