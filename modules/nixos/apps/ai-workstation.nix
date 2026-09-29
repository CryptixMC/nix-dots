{ pkgs, lib, ... }:

let
  scriptWithPath = import ../../../lib/scriptWithPath.nix { inherit lib pkgs; };
  mkUserScript = import ../../../lib/mkUserScript.nix;

  # Hardcoded per-state model tags -- llmfit is run once during bring-up, not looked up live.
  #
  # qwen3-coder:latest -- reliable tool-calling undocked, unlike qwen2.5-coder (prints JSON as prose).
  undockedModel = "qwen3-coder:latest";

  # qwen3:4b -- fits fully in this card's 16GB VRAM (81 tok/s) vs qwen3.6:latest's 31 tok/s.
  # Deliberately differs from Qubi's own docked planner, which keeps
  # qwen3.6:latest for reasoning depth over raw chat speed.
  dockedModel = "qwen3:4b";

  # qubi-state-sync comes from qubi-hwstate.nix's home.packages (user PATH) -- called by bare
  # name via login shell, not store path, matching amd.nix's root-context user-session calls.
  mkSyncScript =
    state: model:
    scriptWithPath {
      name = "ai-workstation-${state}-sync";
      # Explicit PATH (root-context systemd oneshot), matching amd.nix's scripts.
      runtimeInputs = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.bash
      ];
      text = ''
        ${mkUserScript { user = "cryptix"; }}
        log() { echo "[ai-workstation-${state}-sync] $*"; logger -t ai-workstation-${state}-sync "$*"; }

        install -d -m 0755 -o cryptix -g users /run/ai-workstation
        printf '{"state":"${state}","provider":"ollama","model":"%s","updated":"%s"}\n' \
          "${model}" "$(date -Iseconds)" > /run/ai-workstation/state.json
        log "wrote state=${state} model=${model}"

        if as_user bash -lc "qubi-state-sync"; then
          log "qubi-state-sync succeeded"
        else
          log "qubi-state-sync failed or not yet installed — state file is still correct, desktop notification may not have fired"
        fi
      '';
    };
  # NOTE: the former ai-workstation-suspend-evict (Ollama model eviction before
  # suspend) was removed in the Phase 2 closeout alongside Ollama itself — the heavy
  # tier is now llama.cpp (services.qubi.llama.heavy), not Ollama.
in
{
  systemd.tmpfiles.rules = [
    "d /run/ai-workstation 0755 cryptix users -"
  ];

  # Triggered from egpu-bar-fix.service's success branch (amd.nix), reusing its eGPU
  # hotplug detection rather than a second udev rule.
  systemd.services.ai-workstation-dock-sync = {
    description = "Write docked AI-workstation hardware state and notify Goose";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkSyncScript "docked" dockedModel;
    };
  };

  # Triggered from egpu-eject.service's Stage 1 (amd.nix).
  systemd.services.ai-workstation-undock-sync = {
    description = "Write undocked AI-workstation hardware state and notify Goose";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkSyncScript "undocked" undockedModel;
    };
  };

  # Reconciles state at boot -- dock/undock-sync only fire on udev hotplug events, so a
  # boot with no hotplug leaves config.yaml stale. Same lspci detection as gaming-stop.
  systemd.services.ai-workstation-boot-sync = {
    description = "Reconcile AI-workstation dock/undock state at boot";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ai-workstation-boot-sync" ''
        if ${pkgs.pciutils}/bin/lspci -d 1002:73bf | grep -q .; then
          ${pkgs.systemd}/bin/systemctl start ai-workstation-dock-sync.service
        else
          ${pkgs.systemd}/bin/systemctl start ai-workstation-undock-sync.service
        fi
      '';
    };
  };

  # Lets ai-workstation-gaming-stop (home-manager, runs as cryptix) re-derive dock state
  # on game exit without duplicating the model-tag bindings above. Same NOPASSWD pattern as amd.nix.
  security.sudo.extraRules = [
    {
      users = [ "cryptix" ];
      commands = [
        {
          command = "${pkgs.systemd}/bin/systemctl start ai-workstation-dock-sync.service";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.systemd}/bin/systemctl start ai-workstation-undock-sync.service";
          options = [ "NOPASSWD" ];
        }
        # Confines ollama.service to this i7-1260P's E-cores (8-15) while gaming, keeping
        # P-cores free for the game (see qubi-hwstate.nix's gaming start script).
        # sudoers matches exact strings -- gaming-value and restore need separate rules.
        {
          command = "${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota=700% AllowedCPUs=8-15";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota= AllowedCPUs=";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
