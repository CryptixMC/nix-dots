{
  lib,
  pkgs,
  config,
  options,
  inputs,
  ...
}:

let
  home = config.home.homeDirectory;

  # mobile_gui.html is the start_url of the PWA already installed on the phone.
  # Served from the store so no checkout (.git included) reaches the tailnet.
  mobileRoot = pkgs.runCommand "qubi-mobile-root" { } ''
    mkdir -p $out
    cp -r ${inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qubi-app-web}/. $out/
    chmod -R u+w $out
    ln -s index.html $out/mobile_gui.html
  '';
in
{
  imports = [ inputs.qubi.homeModules.qubi ];

  # Qubi versions without `programs.qubi.cli` don't put the Rust CLI on PATH;
  # link just that binary for them.
  home.packages = lib.optionals (!(options.programs.qubi ? cli)) [
    (pkgs.runCommand "qubi-cli" { } ''
      mkdir -p $out/bin
      ln -s ${config.services.qubi.engineRust.package}/bin/qubi $out/bin/qubi
    '')
  ];

  # home-manager writes sessionVariables as `export NAME="value"` without
  # escaping, so the raw JSON's quotes split it into words and abort
  # hm-session-vars.sh before QUBI_SOCKET (sorted after it) is exported.
  home.sessionVariables.QUBI_KNOWN_FOLDERS = lib.mkForce (
    lib.escape [ "\\" "\"" "$" "`" ] (builtins.toJSON config.programs.qubi.knownFolders)
  );

  programs.qubi = {
    enable = true;
    knownFolders = [
      {
        path = "${home}/nix-dots";
        description = "system config, NixOS, Hyprland, Quickshell, home-manager, keybinds, themes";
      }
      {
        path = "${home}/Projects/qubi";
        description = "Qubi itself";
      }
    ];
    # Streaming voice for the app (desktop and phone): live words, Smart Turn,
    # Kokoro replies; the worker starts on the first voice request.

    # `qubi dev` builds from this checkout, and the engine treats it as Qubi's
    # main checkout: its chats edit a qubi/<slug> worktree, never this tree.

    # The Ship button (Releases tab) pins, switches and health-checks from this flake.

    # Placeholder URL: nothing listens there until the NixOS-level
    # services.qubi.searxng is enabled.
    extensions.searxng = config.programs.qubi.mcp.presets.searxng {
      url = "http://127.0.0.1:8888";
    };
  };

  services.qubi.engine = {
    # Written by modules/nixos/apps/ai-workstation.nix on dock/undock/gaming.
    # The Model Lab finds the bench task files here; the llama-server and
    # `qubi-coding-bench` it resolves itself.
    environment.QUBI_LAB_REPO = "${home}/Projects/qubi";
  };

  services.qubi.engineRust = {
    enable = true;
    package = inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qubi-engine;
    # Null by default in the qubi hm-module; setting them enables the
    # "claude" and "qwen-local" agents and delegate_to_local.
    agents = {
      claudeAgentAcpPackage = inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.claude-agent-acp;
      qwenCodePackage = inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qwen-code;
    };
  };

  # The desktop app (Tauri); it reaches the engine over its local socket.
  services.qubi.modules.app.enable = true;

  services.qubi.modules.app.serve = {
    enable = true;
    package = mobileRoot;
    tailscaleServe.enable = true;
  };

  # The Rust engine's network transport for the phone: paired devices over a
  # WebSocket behind `tailscale serve` (never Funnel). rpId and origin are this
  # node's tailnet HTTPS name, which WebAuthn approvals are bound to.
  services.qubi.modules.net = {
    enable = true;
    rpId = "carbon.tail691394.ts.net";
    origin = "https://carbon.tail691394.ts.net";
    # Devices signed in as this login get a token without a pairing code.
    trustedTailnetLogins = [ "cryptixmc@proton.me" ];
  };

  # One local model: the 9B on the eGPU when docked (64K context, two slots so
  # a second chat does not evict the prompt cache), the CPU otherwise. Every
  # role names it; API models come through provider modules.
  services.qubi.modules.llama = {
    fast.enable = false;
    light.enable = false;
    heavy.enable = false;
    models."qwen3.5-9b" = {
      modelFile = "Qwen3.5-9B-Q4_K_M.gguf";
      port = 8095;
      contextSize = 65536;
      parallel = 2;
      memoryMax = "32G";
      placement = "auto";
      gpu = {
        enable = true;
        vramMb = 8500;
        renderNode = "/dev/dri/by-path/pci-0000:54:00.0-render";
      };
      tags = [ "quick answers" "tool calling" "file edits" "planning" "research" "coding" ];
    };
    gpu.mode = "fit_beside_game";
  };
  services.qubi.engineRust.roles = {
    talk.models = [ "qwen3.5-9b" ];
    build.models = [ "qwen3.5-9b" ];
    deep.models = [ "qwen3.5-9b" ];
  };

  # OpenRouter on the engine's own tool loop. The key stays in a file only the
  # user writes; nothing is routed here until tierModels or the bench asks.
  # The held-out sections every night on the docked GPU; regressions become roadmap proposals.
  services.qubi.modules.lab.nightly = {
    enable = true;
    hour = 3;
    model = "/home/cryptix/.local/share/qubi/models/Qwen3.5-9B-Q4_K_M.gguf";
    repo = "/home/cryptix/Projects/qubi";
  };

  services.qubi.engineRust.providers.openrouter = {
    url = "https://openrouter.ai/api/v1";
    keyFile = "/home/cryptix/.config/qubi/secrets/openrouter.key";
    headers = {
      "HTTP-Referer" = "https://github.com/cryptix/qubi";
      "X-Title" = "Qubi";
    };
    dailyUsdCap = 2.0;
  };

  services.qubi.modules.shell.path = "${home}/nix-dots/desktop/shell";
  services.qubi.modules.voice.cli.enable = true;
  services.qubi.modules.voice.enable = true;
  services.qubi.modules.voice.voicedPackage = inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qubi-voiced;
  services.qubi.modules.develop.checkout = "${home}/Projects/qubi";
  services.qubi.modules.release.flake = "${home}/nix-dots";
  services.qubi.modules.llama.hwStateFile = "/run/ai-workstation/state.json";
  services.qubi.modules = {
    develop.enable = true;
    release.enable = true;
    import.enable = true;
    lab.enable = true;
    llama.enable = true;
    shell.enable = true;
  };
}
