{ ... }:

{
  programs.nvf = {
    enable = true;
    settings.vim = {
      viAlias = true;
      vimAlias = true;

      theme = {
        enable = true;
        name = "catppuccin";
        style = "mocha";
      };

      languages = {
        enableLSP = true;
        enableFormat = true;
        enableTreesitter = true;

        nix.enable = true;
        nix.format = {
          enable = true;
          type = "nixfmt";
        };
        nix.lsp.enable = true;

        rust.enable = true;
        python.enable = true;
        markdown.enable = true;
        bash.enable = true;
      };

      git.enable = true;

      ui = {
        borders.enable = true;
        noice.enable = true;
        colorizer.enable = true;
        illuminate.enable = true;
      };

      binds = {
        cheatsheet.enable = true;
        whichKey.enable = true;
      };

      #nvchad.enable = true;
      telescope.enable = true;
    };
  };
}
