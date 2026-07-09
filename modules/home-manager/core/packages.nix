{ pkgs, ... }:
{
  home.packages = with pkgs; [
    neovim
    prismlauncher
    brightnessctl
    nixd
    nil
    vinegar
    easyeffects
    lsp-plugins
    rnnoise-plugin
    calf
    tenacity
    seahorse
  ];
}
