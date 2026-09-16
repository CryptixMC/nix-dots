{ pkgs, lib, ... }:

let
  # Hardcoded per Phase 1b's design (llmfit is run once per state during
  # bring-up, not looked up live) — see the "Local-First AI Workstation"
  # plan doc for the full candidate lists these were chosen from.
  #
  # Undocked: chosen 2026-09-11 from `llmfit recommend --use-case coding
  # --min-fit good -n 40` on live CPU+iGPU hardware (no eGPU attached).
  # qwen2.5-coder:7b was picked as the CPU-viable middle ground (score 81,
  # ~11.6 tok/s estimated) over the already-installed llama3.2:3b (faster
  # but lower quality) and qwen2.5-coder:14b (better quality, noticeably
  # slower on pure CPU inference).
  undockedModel = "qwen2.5-coder:14b";

  # Docked: after a clean reboot restored ROCm/KFD visibility, a live
  # `llmfit recommend --use-case coding --min-fit good -n 40` with the
  # eGPU's real 16GB VRAM detected only surfaced small (≤7B) Ollama-tagged
  # options — a database-coverage gap in llmfit (it hasn't mapped larger
  # models to Ollama tags), not a real fitness verdict on this hardware.
  # Deliberately kept as the already-installed, already-verified-loadable
  # qwen3.6:latest (23GB, see README's documented 36B-model load test)
  # instead, since real-world proof outweighs llmfit's sparse database here.
  dockedModel = "qwen3.6:latest";

  # PATH explicitly set (not inherited) since these run as root-context
  # systemd oneshots, matching the convention in
  # modules/nixos/hardware/amd.nix's scripts.
  scriptPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.bash
  ];

  # goose-state-sync is provided by modules/home-manager/apps/goose.nix's
  # home.packages, landing on the user's normal profile PATH — referenced
  # by bare name here (via a login shell for PATH resolution) rather than
  # stitched across the NixOS/home-manager module boundary by store path,
  # matching how amd.nix's root-context scripts already call user-session
  # commands (kanshi.service, hyprctl) by name via runuser. Verify this
  # resolves correctly the first time these units actually fire.
  mkSyncScript = state: model: pkgs.writeShellScript "ai-workstation-${state}-sync" ''
    PATH=${scriptPath}:$PATH
    log() { echo "[ai-workstation-${state}-sync] $*"; logger -t ai-workstation-${state}-sync "$*"; }

    install -d -m 0755 -o cryptix -g users /run/ai-workstation
    printf '{"state":"${state}","provider":"ollama","model":"%s","updated":"%s"}\n' \
      "${model}" "$(date -Iseconds)" > /run/ai-workstation/state.json
    log "wrote state=${state} model=${model}"

    if runuser -u cryptix -- env XDG_RUNTIME_DIR="/run/user/$(id -u cryptix)" bash -lc "goose-state-sync"; then
      log "goose-state-sync succeeded"
    else
      log "goose-state-sync failed or not yet installed — state file is still correct, desktop notification may not have fired"
    fi
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /run/ai-workstation 0755 cryptix users -"
  ];

  # Triggered by an added line in egpu-bar-fix.service's success branch
  # (modules/nixos/hardware/amd.nix) — not by its own udev rule, reusing
  # the existing eGPU hotplug detection rather than building a second one.
  systemd.services.ai-workstation-dock-sync = {
    description = "Write docked AI-workstation hardware state and notify Goose";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkSyncScript "docked" dockedModel;
    };
  };

  # Triggered by an added line in egpu-eject.service's Stage 1 (amd.nix).
  systemd.services.ai-workstation-undock-sync = {
    description = "Write undocked AI-workstation hardware state and notify Goose";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mkSyncScript "undocked" undockedModel;
    };
  };

  # Reconciles state at boot — dock/undock-sync above only ever fire on a
  # udev hotplug event (amd.nix's egpu-bar-fix/egpu-eject), so a boot with
  # no hotplug event (the common case: the eGPU's presence doesn't change
  # across a reboot) left goose-state-sync never re-run, silently keeping
  # config.yaml on whatever state a prior session last wrote. Same
  # lspci-based detection ai-workstation-gaming-stop already uses.
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

  # Lets ai-workstation-gaming-stop (home-manager script, runs as cryptix)
  # re-derive real docked/undocked state on game exit without duplicating
  # the model-tag `let` bindings above in a second location — same scoped-
  # NOPASSWD-for-one-command pattern already used for egpu-eject.service
  # in modules/nixos/hardware/amd.nix.
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
      ];
    }
  ];
}
