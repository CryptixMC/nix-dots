{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  cfg = config.programs.qubi;
  eng = config.services.qubi.engine;
  mob = config.services.qubi.mobile;

  jsonFormat = pkgs.formats.json { };
  yamlFormat = pkgs.formats.yaml { };

  # Everything the Python package refuses to hardcode (python/src/qubi/
  # paths.py). Set on the engine unit AND as session variables, so the CLIs
  # a human runs by hand (qubi-bench, qubi-hwstate) resolve the same
  # locations the daemon does. Unset values fall through to the package's
  # own defaults.
  qubiEnv =
    lib.filterAttrs (_: v: v != null) {
      QUBI_DEFAULT_CWD = cfg.defaultCwd;
      QUBI_SHELL_PATH = cfg.shellPath;
      QUBI_THEMES_DIR = cfg.themesDir;
      QUBI_HW_STATE_FILE = eng.hwStateFile;
      QUBI_OLLAMA_URL = eng.ollamaUrl;
    }
    // eng.environment;

  # Goose launches an extension by absolute path with whatever environment
  # the launching goose happens to have (the engine's, a terminal's, Goose
  # Desktop's), so the one setting ask_user needs is pinned in a wrapper
  # rather than trusted to be inherited.
  askUserCmd = pkgs.writeShellScript "qubi-ask-user-mcp" ''
    ${lib.optionalString (cfg.shellPath != null) ''export QUBI_SHELL_PATH=${lib.escapeShellArg cfg.shellPath}''}
    exec ${cfg.package}/bin/qubi-ask-user-mcp
  '';

  qubiExtensions =
    lib.optionalAttrs cfg.mcp.askUser.enable {
      ask-user = {
        enabled = true;
        type = "stdio";
        name = "ask-user";
        display_name = "Ask User";
        description = "Ask the human a multiple-choice or free-text question and block for a real answer via an on-screen dialog";
        cmd = "${askUserCmd}";
        args = [ ];
        bundled = false;
        # ask_user's own 300s internal timeout bounds the worst case.
        timeout = 310;
      };
    }
    // lib.optionalAttrs cfg.mcp.notesCapture.enable {
      notes-capture = {
        enabled = true;
        type = "stdio";
        name = "notes-capture";
        display_name = "Notes Capture";
        description = "Append a structured note (title, summary, links, tags) to the capture inbox";
        cmd = "${cfg.package}/bin/qubi-notes-capture-mcp";
        args = [ ];
        bundled = false;
        timeout = 60;
      };
    };

  gooseSettings = lib.recursiveUpdate { extensions = qubiExtensions; } cfg.goose.settings;
  gooseConfigFile = yamlFormat.generate "goose-config.yaml" gooseSettings;

  initOverlay = jsonFormat.generate "qubi-config-overlay.json" eng.initialConfig;
in
{
  options.programs.qubi = {
    enable = mkEnableOption "Qubi, a multi-tier local-first assistant in front of goose";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The qubi Python package (engine, CLIs, MCP servers).";
    };

    defaultCwd = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/alice/src";
      description = "Working directory new goose sessions are created in. Null means the home directory.";
    };

    shellPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/alice/.config/quickshell";
      description = ''
        Config directory of the Quickshell instance that embeds Qubi's QML
        (`quickshell -p <path>`); the ask-user MCP server raises its dialog
        there. Null means Quickshell's default config.
      '';
    };

    themesDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Directory of `<name>/base16.yaml` (+ optional `theme.json`) themes
        served to clients without filesystem access via `qubi/theme`.
      '';
    };

    mcp = {
      askUser.enable = mkEnableOption "the ask-user goose extension" // {
        default = true;
      };
      notesCapture.enable = mkEnableOption "the notes-capture goose extension" // {
        default = true;
      };
    };

    goose = {
      manageConfig = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Generate `~/.config/goose/config.yaml` from {option}`settings`.
          Goose rewrites that file at runtime (e.g. an interactive `/model`),
          so it is installed as a real file on every activation rather than
          symlinked, after backing up any drifted copy to
          `config.yaml.pre-nix-<epoch>`. Off by default: without it Qubi
          uses whatever goose config already exists.
        '';
      };

      settings = mkOption {
        type = yamlFormat.type;
        default = { };
        description = ''
          Contents of goose's config.yaml. Qubi's own extensions (see
          {option}`programs.qubi.mcp`) are merged in under `extensions`;
          an entry here with the same name wins.
        '';
      };

      extensionCommands = mkOption {
        type = types.attrsOf types.str;
        readOnly = true;
        description = "Absolute commands of Qubi's MCP servers, for referencing from recipes.";
      };

      extraInstructions = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Written to `~/.config/goose/AGENTS.md`, goose's global instruction file.";
      };

      recipes = mkOption {
        type = types.attrsOf types.lines;
        default = { };
        description = "Goose recipes, written to `~/.config/goose/recipes/<name>.yaml`.";
      };
    };

    voice.enable = mkEnableOption "the voice-transcribe / voice-speak CLIs the voice overlay shells out to";
  };

  options.services.qubi.engine = {
    enable = mkEnableOption "the qubi-engine user service" // {
      default = true;
    };

    ws = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Serve the websocket transport (needed by the mobile PWA).";
      };
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Websocket bind address. The engine has no authentication; keep it on loopback and front it with something that does.";
      };
      port = mkOption {
        type = types.port;
        default = 8765;
        description = "Websocket port.";
      };
    };

    ollamaUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://127.0.0.1:11434";
      description = "Ollama base URL. Null means the package default.";
    };

    hwStateFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/ai-workstation/state.json";
      description = ''
        Optional JSON file `{"state": "docked" | "undocked" | "gaming"}`
        written by whatever manages this machine's GPU (see
        docs/hw-state.md). A missing file means "docked".
      '';
    };

    initialConfig = mkOption {
      type = jsonFormat.type;
      default = { };
      example = lib.literalExpression ''{ tiers.light.model = "gemma3:4b"; }'';
      description = ''
        Deep-merged over the built-in defaults when
        `~/.config/qubi/config.json` is first created. That file is
        user-authoritative afterwards and is never overwritten by an
        activation; change it with `qubi-config set`.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment for the engine and the Qubi CLIs.";
    };
  };

  options.services.qubi.mobile = {
    enable = mkEnableOption "the static file server for the mobile PWA";

    root = mkOption {
      type = types.path;
      description = ''
        Directory to serve. Must contain only the PWA: it is published
        as-is, so never point it at a checkout.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 8901;
      description = "Loopback port of the static file server.";
    };

    tailscaleServe.enable = mkEnableOption ''
      publishing the PWA at `/` and the engine websocket at `/ws` on this
      node's tailnet HTTPS address via `tailscale serve`
    '';
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = [ cfg.package ];
      home.sessionVariables = qubiEnv;

      programs.qubi.goose.extensionCommands = lib.mapAttrs (_: e: e.cmd) qubiExtensions;

      # The one file an activation must NEVER clobber: tiers/routing/theme
      # are meant to be edited live (by hand or a settings UI) without a
      # rebuild. `qubi-config init` only writes when nothing exists yet.
      home.activation.qubiConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${cfg.package}/bin/qubi-config init --overlay ${initOverlay}
      '';

      home.file = lib.mapAttrs' (
        name: text: lib.nameValuePair ".config/goose/recipes/${name}.yaml" { inherit text; }
      ) cfg.goose.recipes;
    }

    (mkIf (cfg.goose.extraInstructions != null) {
      home.file.".config/goose/AGENTS.md".text = cfg.goose.extraInstructions;
    })

    (mkIf cfg.goose.manageConfig {
      # Kept next to the live file so drift is one `diff` away.
      home.file.".config/goose/config.yaml.nix-source".source = gooseConfigFile;

      # Reads the store path directly, not the home.file symlink above:
      # activation order is writeBoundary -> custom scripts -> linkGeneration,
      # so the symlink does not exist yet when this runs.
      home.activation.gooseConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        configDir="$HOME/.config/goose"
        configFile="$configDir/config.yaml"
        nixSource="${gooseConfigFile}"

        run mkdir -p "$configDir"

        if [ -e "$configFile" ] && ! cmp -s "$configFile" "$nixSource" 2>/dev/null; then
          run cp "$configFile" "$configDir/config.yaml.pre-nix-$(date +%s)"
        fi

        run install -m 0644 "$nixSource" "$configFile"
      '';
    })

    (mkIf eng.enable {
      # Restart=on-failure, not "always": a crash-looping engine must not
      # hammer Ollama in a tight loop. After=graphical-session.target since
      # its tier processes assume a live user session.
      systemd.user.services.qubi-engine = {
        Unit = {
          Description = "Qubi engine: persistent multi-tier goose acp router (unix socket + websocket)";
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${cfg.package}/bin/qubi-engine";
          Environment = lib.mapAttrsToList (k: v: "${k}=${v}") (
            qubiEnv
            // {
              PYTHONUNBUFFERED = "1";
              QUBI_WS_ENABLE = lib.boolToString eng.ws.enable;
              QUBI_WS_HOST = eng.ws.host;
              QUBI_WS_PORT = toString eng.ws.port;
            }
          );
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    (mkIf mob.enable {
      systemd.user.services.qubi-mobile-static = {
        Unit.Description = "Static file server for the Qubi mobile PWA";
        Service = {
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString mob.port} --bind 127.0.0.1 --directory ${mob.root}";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    (mkIf (mob.enable && mob.tailscaleServe.enable) {
      assertions = [
        {
          assertion = eng.enable && eng.ws.enable;
          message = "services.qubi.mobile.tailscaleServe needs services.qubi.engine with ws.enable.";
        }
      ];

      # Loopback-only backends: tailscale serve is the sole tailnet-facing
      # surface. (Binding the static server to the tailscale IP instead was
      # a real 502 -- serve connects over loopback.) `serve`, never `funnel`,
      # which would expose this to the public internet. Idempotent, so
      # re-asserting on every login is safe and self-healing; a oneshot
      # because `serve --bg` persists in tailscaled, not in this process.
      # Serve has to be approved once per tailnet at a URL `tailscale serve`
      # prints; until then this unit fails harmlessly.
      systemd.user.services.qubi-tailscale-serve = {
        Unit = {
          Description = "Expose qubi-engine/qubi-mobile-static over tailscale serve (HTTPS, tailnet-only)";
          After = [
            "qubi-engine.service"
            "qubi-mobile-static.service"
            "tailscaled.service"
          ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "qubi-tailscale-serve-setup" ''
            set -uo pipefail
            ${pkgs.tailscale}/bin/tailscale serve --bg --set-path /ws http://localhost:${toString eng.ws.port}
            ${pkgs.tailscale}/bin/tailscale serve --bg --set-path / http://localhost:${toString mob.port}
          '';
        };
        Install.WantedBy = [ "default.target" ];
      };
    })

    (mkIf cfg.voice.enable (import ./voice.nix { inherit pkgs lib; }))
  ]);
}
