{ pkgs, lib, ... }:
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
    amdgpu_top
    seahorse
    google-chrome
    obsidian
    gh
    nodejs
    supabase-cli
  ];

  # Vercel CLI isn't packaged in nixpkgs (fast-moving, npm-only, no
  # standalone binary release), so install it via npm into an isolated
  # prefix on every activation instead of a proper derivation.
  home.sessionPath = [ "$HOME/.npm-global/bin" ];

  home.activation.installVercelCli = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${pkgs.nodejs}/bin:$PATH"
    export NPM_CONFIG_PREFIX="$HOME/.npm-global"
    run mkdir -p "$NPM_CONFIG_PREFIX"
    run ${pkgs.nodejs}/bin/npm install -g vercel --silent
  '';
}
