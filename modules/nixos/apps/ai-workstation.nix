{ pkgs, lib, ... }:

let
  # Hardcoded per Phase 1b's design (llmfit is run once per state during
  # bring-up, not looked up live) — see the "Local-First AI Workstation"
  # plan doc for the full candidate lists these were chosen from.
  #
  # Undocked: superseded 2026-09-16 by Part II's Stage 2 roster benchmark.
  # qwen2.5-coder (7b/14b) reliably printed tool-call JSON as prose instead
  # of invoking it — 0% real tool-calling success across every test this
  # repo ever ran against it. qwen3-coder:latest (30.5B MoE, ~3B active) was
  # excluded from all earlier CPU testing purely for its 18GB total size;
  # once actually measured CPU-only it passed 5/6 real tasks (append/read/
  # edit-verify, with and without thinking) — slow (71-928s) but correct
  # and tool-calling-reliable, which qwen2.5-coder never was at any speed.
  # This drives the chat overlay/general-assistant role when undocked — CPU
  # inference has no "fits in VRAM" speedup to chase, so there's no reason
  # to split from goose-code's own undocked coding pick (same model, see
  # modules/home-manager/apps/goose.nix's gooseCode).
  undockedModel = "qwen3-coder:latest";

  # Docked: superseded again 2026-09-17 by the /goal speed target (general
  # chat + light coding should hit ~50 tok/s where achievable). Native
  # measurement on this exact hardware: qwen3.6:latest generates at only
  # 31.25 tok/s despite being the reasoning-strongest model available —
  # dense-enough and large enough (23GB) that it doesn't fully fit this
  # card's 16GB VRAM. qwen3:4b, dense and small enough to load 100% GPU
  # (4.0GB resident), measured at 81.0 tok/s native generation and passed
  # 3/3 real goose-bench tasks (append/read/edit-verify, thinking off) —
  # a genuine reversal of qwen3:4b's original-session rejection, which was
  # measured against the since-fixed 15K-token bloated config, not a real
  # model limitation. This value drives the chat overlay's default docked
  # model (general chat/assistant role) — NOT goose-code's docked planner,
  # which keeps qwen3.6:latest deliberately (planning benefits from more
  # reasoning depth more than chat needs raw speed; see goose.nix).
  dockedModel = "qwen3:4b";

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
