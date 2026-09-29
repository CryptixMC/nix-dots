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

  # Heavy tier on the eGPU, stopped/started on undock/dock by amd.nix; undocked
  # it falls back to CPU. Use the by-path render node: renderD* can renumber.
  services.qubi.llama.heavy = {
    enable = true;
    modelFile = "Qwen3-Coder-30B-A3B-Instruct-UD-Q3_K_XL.gguf";
    renderNode = "/dev/dri/by-path/pci-0000:54:00.0-render";
  }
  # Only set when the pinned qubi has the option, so bumping flake.lock
  # (not this file) is what turns it on.
  // lib.optionalAttrs (options.services.qubi.llama.heavy ? cpuFallback) {
    cpuFallback.enable = true;
  };
}
