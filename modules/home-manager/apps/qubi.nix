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
    cp -r ${inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qubi-mobile}/. $out/
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
    shellPath = "${home}/nix-dots/desktop/shell";
    themesDir = "${home}/nix-dots/desktop/themes";
    voice.enable = true;

    # `qubi dev` builds from this checkout, and the engine treats it as Qubi's
    # main checkout: its chats edit a qubi/<slug> worktree, never this tree.
    dev.checkout = "${home}/Projects/qubi";

    # Placeholder URL: nothing listens there until the NixOS-level
    # services.qubi.searxng is enabled.
    extensions.searxng = config.programs.qubi.mcp.presets.searxng {
      url = "http://127.0.0.1:8888";
    };
  };

  services.qubi.engine = {
    # Written by modules/nixos/apps/ai-workstation.nix on dock/undock/gaming.
    hwStateFile = "/run/ai-workstation/state.json";
    backend = "rust";
    # The Model Lab finds the bench task files here; the llama-server and
    # `qubi-coding-bench` it resolves itself.
    environment.QUBI_LAB_REPO = "${home}/Projects/qubi";
  };

  # The Python engine stays installed; `backend = "rust"` only picks which
  # socket QUBI_SOCKET points clients at.
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

  services.qubi.mobile = {
    enable = true;
    root = mobileRoot;
    tailscaleServe.enable = true;
  };

  # The Rust engine's network transport for the phone: paired devices over a
  # WebSocket behind `tailscale serve` (never Funnel). rpId and origin are this
  # node's tailnet HTTPS name, which WebAuthn approvals are bound to.
  services.qubi.net = {
    enable = true;
    rpId = "carbon.tail691394.ts.net";
    origin = "https://carbon.tail691394.ts.net";
  };

  # Heavy tier on the eGPU, stopped/started on undock/dock by amd.nix; undocked
  # it falls back to CPU. Use the by-path render node: renderD* can renumber.
  # 26 of 30 on the heavy tier suite at 5.7 GB. The 30B coder this replaces
  # fills the card and has dropped it off the bus under load.
  services.qubi.llama.heavy = {
    enable = true;
    modelFile = "Qwen3.5-9B-Q4_K_M.gguf";
    extraArgs = [
      "--reasoning-budget"
      "0"
    ];
    renderNode = "/dev/dri/by-path/pci-0000:54:00.0-render";
  }
  # Only set when the pinned qubi has the option, so bumping flake.lock
  # (not this file) is what turns it on.
  // lib.optionalAttrs (options.services.qubi.llama.heavy ? cpuFallback) {
    cpuFallback.enable = true;
  };

  # Beats Qwen3-1.7B on the fast-tier suite (31/40 against 25/40). Its hybrid
  # attention cannot restore a saved slot, so the first request after a unit
  # start re-reads the prompt.
  services.qubi.llama.fast.modelFile = "Qwen3.5-2B-Q4_K_M.gguf";

  # Run fast and light on the eGPU when it is docked; share it with a game.
  services.qubi.llama.fast.gpu.enable = true;
  services.qubi.llama.light.gpu.enable = true;
  services.qubi.llama.gpuPlacement.mode = "fit_beside_game";
  services.qubi.llama.gpuPlacement.heavyVramMb = 7500;
}
