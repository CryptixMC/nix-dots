{ pkgs, lib, ... }:

let
  scriptWithPath = import ../../../lib/scriptWithPath.nix { inherit lib pkgs; };
  mkUserScript = import ../../../lib/mkUserScript.nix;

  # Per-state model tags, chosen once rather than looked up live.
  # qwen3-coder: reliable tool-calling (qwen2.5-coder prints JSON as prose).
  undockedModel = "qwen3-coder:latest";

  # qwen3:4b fits fully in 16GB VRAM; Qubi's planner deliberately uses a larger model.
  dockedModel = "qwen3:4b";

  # qubi-state-sync is on the user's PATH (qubi-hwstate.nix), so call it via a login shell.
  mkSyncScript =
    state: model:
    scriptWithPath {
      name = "ai-workstation-${state}-sync";
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
in
{
  systemd.tmpfiles.rules = [
    "d /run/ai-workstation 0755 cryptix users -"
  ];

  # Started by boot-sync below and by the gaming-stop script (qubi-hwstate.nix).
  systemd.services.ai-workstation-dock-sync = {
    description = "Write docked AI-workstation hardware state and notify Goose";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkSyncScript "docked" dockedModel;
    };
  };

  systemd.services.ai-workstation-undock-sync = {
    description = "Write undocked AI-workstation hardware state and notify Goose";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkSyncScript "undocked" undockedModel;
    };
  };

  # Reconciles dock state at boot, when no hotplug event fires.
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

  # Lets the user-level gaming-stop script re-derive dock state on game exit.
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
        # Pins ollama to the E-cores (8-15) while gaming. sudoers matches exact
        # strings, so set and restore need separate rules.
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
