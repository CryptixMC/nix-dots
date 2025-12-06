{ pkgs, lib, ... }:

{
  stylix.targets.zed.enable = true;
  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;

    extensions = [
      "nix"
      "toml"
      "make"
    ];

    userSettings = {
      hour_format = "hour24";
      auto_update = false;
      terminal = {
        alternate_scroll = "off";
        blinking = "off";
        copy_on_select = false;
        dock = "bottom";
        detect_venv = {
          on = {
            directories = [
              ".env"
              "env"
              ".venv"
              "venv"
            ];
            activate_script = "default";
          };
        };
        env = {
          TERM = "kitty";
        };

        shell = "system";
        program = "zsh";

        toolbar = {
          title = true;
        };
        working_directory = "current_project_directory";
      };
      lsp = {
        rust-analyzer = {
          binary = {
            path_lookup = true;
          };
        };
        nix = {
          binary = {
            path_lookup = true;
          };
        };
      };
      languages = {
      };
      vim_mode = false;
      load_direnv = "shell_hook";
      base_keymap = "VSCode";
      ui_font_size = lib.mkForce 16;
      buffer_font_size = lib.mkForce 16;
    };
  };

}
