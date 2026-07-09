{ pkgs, lib, ... }:
{
  stylix.targets.zed.enable = true;
  programs.zed-editor = {
    enable = true;
    package = pkgs.symlinkJoin {
      name = "zed-editor";
      paths = [ pkgs.zed-editor ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/zeditor \
          --set CLAUDE_CODE_EXECUTABLE "${pkgs.claude-code}/bin/claude"
      '';
    };
    extensions = [
      "nix"
      "toml"
      "make"
    ];
    userSettings = {
      hour_format = "hour24";
      auto_update = false;

      assistant = {
        enabled = true;
        version = "2";
        default_model = {
          provider = "anthropic";
          model = "claude-sonnet-4-5";
        };
        agent_servers = {
          "claude-acp" = {
            type = "registry";
            env = {
              PATH = "/run/wrappers/bin:/home/cryptix/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
              CLAUDE_CODE_EXECUTABLE = "/run/current-system/sw/bin/claude";
            };
          };
        };
      };

      agent = {
        enabled = true;
        agent_servers = {
          "claude-acp" = {
            type = "registry";
            env = {
              PATH = "/run/wrappers/bin:/home/cryptix/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
              CLAUDE_CODE_EXECUTABLE = "/run/current-system/sw/bin/claude";
            };
          };
        };
      };

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
        rust-analyzer.binary.path_lookup = true;
        nix.binary.path_lookup = true;
      };

      languages = { };
      vim_mode = false;
      load_direnv = "shell_hook";
      base_keymap = "VSCode";
      ui_font_size = lib.mkForce 16;
      buffer_font_size = lib.mkForce 16;
    };
  };
}
