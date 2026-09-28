{
  pkgs,
  config,
  inputs,
  ...
}:

let
  home = config.home.homeDirectory;

  # The PWA itself comes from the qubi tree. The only thing added here is
  # the URL it used to live at, which the copy installed on the phone still
  # has as its start_url. (Served from the store: the static server used to
  # publish the whole checkout, .git included, to the tailnet.)
  mobileRoot = pkgs.runCommand "qubi-mobile-root" { } ''
    mkdir -p $out
    cp -r ${inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qubi-mobile}/. $out/
    ln -s index.html $out/mobile_gui.html
  '';
in
{
  imports = [ inputs.qubi.homeModules.qubi ];

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
    shellPath = "${home}/nix-dots/quickshell";
    themesDir = "${home}/nix-dots/themes";
    voice.enable = true;
    # programs.qubi.goose.* is set in ./goose.nix.

    # Phase 4 Step 7 gate: "adding mcp-searxng is config-only." Placeholder
    # URL -- nix/nixos-module.nix's services.qubi.searxng module isn't
    # enabled on this host, so nothing is listening at 127.0.0.1:8888 yet;
    # this still proves the config-only wiring (the mcp-searxng process
    # starts, a web_search tool is exposed, zero crates/ edits needed).
    # Enable services.qubi.searxng (NixOS-level) separately for a fully
    # working instance.
    extensions.searxng = config.programs.qubi.mcp.presets.searxng {
      url = "http://127.0.0.1:8888";
    };
  };

  services.qubi.engine = {
    # Written by modules/nixos/apps/ai-workstation.nix on every dock/
    # undock/gaming transition.
    hwStateFile = "/run/ai-workstation/state.json";
    backend = "rust";
  };

  # Phase 3 Step 5 installed the Rust engine alongside the Python one; Step 6
  # flips services.qubi.engine.backend to "rust" above, so Quickshell now
  # reads QUBI_SOCKET pointed at this engine's socket. The Python engine's
  # own unit stays installed/enabled -- this only changes which socket
  # clients are told to use.
  services.qubi.engineRust = {
    enable = true;
    package = inputs.qubi.packages.${pkgs.stdenv.hostPlatform.system}.qubi-engine;
    # Phase 5 Step 1/4/6: real child-agent packages, wired here (deliberately
    # left null in the qubi flake's own hm-module.nix -- see its comment on
    # `package` above for why). Enables the "claude" and "qwen-local" agent
    # manifest entries and the delegate_to_local mcp entry.
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

  # Phase 2 DOCKED Step 4: heavy tier, docked-only (stopped/started by
  # qubi-gpu-release/qubi-gpu-attach on eGPU undock/dock, see
  # modules/nixos/hardware/amd.nix). Render node is this host's stable
  # by-path symlink for the eGPU (matches the iGPU pin convention used by
  # the greeter fix elsewhere in this tree) -- never the raw renderD*
  # name, which can renumber.
  services.qubi.llama.heavy = {
    enable = true;
    modelFile = "Qwen3-Coder-30B-A3B-Instruct-UD-Q3_K_XL.gguf";
    renderNode = "/dev/dri/by-path/pci-0000:54:00.0-render";
  };
}
