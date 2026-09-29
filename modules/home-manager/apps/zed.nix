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
      # Overrides stylix's build-time theme with the one Theme.qml writes live to
      # ~/.config/zed/themes/quickshell-live.json.
      theme = lib.mkForce "Quickshell Live";

      hour_format = "hour24";
      auto_update = false;
      cli_default_open_behavior = "existing_window";
      vim_mode = false;
      load_direnv = "shell_hook";
      base_keymap = "VSCode";
      proxy = "";

      ui_font_size = lib.mkForce 16;
      buffer_font_size = lib.mkForce 16;

      edit_predictions = {
        mode = "subtle";
      };

      project_panel.dock = "left";
      outline_panel.dock = "left";
      collaboration_panel.dock = "left";
      git_panel = {
        dock = "left";
        tree_view = true;
      };

      assistant = {
        enabled = true;
        version = "2";
        default_model = {
          provider = "anthropic";
          model = "claude-sonnet-4-6";
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
        default_model = {
          provider = "anthropic";
          model = "claude-sonnet-4-6";
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

      agent_servers = {
        "claude-acp" = {
          type = "registry";
          default_config_options = {
            model = "sonnet";
            mode = "bypassPermissions";
          };
          favorite_config_option_values = {
            mode = [
              "bypassPermissions"
              "plan"
            ];
          };
        };
      };

      ssh_connections = [
        {
          host = "10.0.0.166";
          username = "cryptix";
          args = [ ];
          nickname = "Raspberry Pi";
          projects = [
            { paths = [ "/home/cryptix/./" ]; }
            { paths = [ "/home/cryptix/Projects/./" ]; }
          ];
        }
      ];

      # mcp-server-github's token is kept out of git; the merge activation script
      # preserves it from the live settings.json.
      context_servers = {
        "mcp-server-supabase" = {
          enabled = true;
          remote = false;
          settings = { };
        };
        "mcp-server-puppeteer" = {
          enabled = true;
          remote = false;
          settings = { };
        };
        "mcp-server-playwright" = {
          enabled = true;
          remote = false;
          settings = { };
        };
        "mcp-server-memory" = {
          enabled = true;
          remote = false;
          settings = {
            memory_file_path = "";
          };
        };
        "mcp-server-github" = {
          enabled = true;
          remote = false;
          settings = { };
        };
      };

      lsp = {
        rust-analyzer.binary.path_lookup = true;
        nix.binary.path_lookup = true;
      };

      languages = { };

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
    };

    userKeymaps = builtins.fromJSON (builtins.readFile ./zed-keymap.json);
  };
}
