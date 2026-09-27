{ pkgs, lib, ... }:

let
  # Notifies on dock/undock/gaming state changes. Notification only --
  # qubi-engine watches the same state file and handles model selection
  # itself; config.yaml stays Nix-generated and static.
  #
  # Relocated out of the former goose.nix (Phase 5 Step 10, goose removal) --
  # this is a hardware-state tenant, not goose-specific: ai-workstation.nix's
  # dock/undock hooks call it by bare name via a login shell
  # (`as_user bash -lc "qubi-state-sync"`), and it must stay on the user's
  # PATH independent of whether goose is installed at all.
  qubiStateSync = pkgs.writeShellScriptBin "qubi-state-sync" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.yq-go
        pkgs.hyprland
      ]
    }:$PATH

    STATE_FILE=/run/ai-workstation/state.json

    # A login shell via `runuser ... bash -lc` doesn't inherit the desktop
    # session's env; rediscover it the way amd.nix's hyprctl_user() does.
    export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -n1)

    if [ ! -f "$STATE_FILE" ]; then
      echo "[qubi-state-sync] no state file at $STATE_FILE yet — nothing to sync" >&2
      exit 0
    fi

    # -r unwraps the scalar; without it yq keeps the JSON source's
    # double-quote style and prints literal quote characters.
    state=$(yq -r '.state' "$STATE_FILE")
    provider=$(yq -r '.provider' "$STATE_FILE")

    if [ "$state" = "gaming" ] || [ "$provider" = "null" ]; then
      hyprctl notify -1 4000 "rgb(89dceb)" "Gaming: local model evicted (chat overlay routing unchanged)" 2>/dev/null || true
    else
      hyprctl notify -1 4000 "rgb(89dceb)" "AI tier: $state — qubi switched to its $state models" 2>/dev/null || true
    fi
  '';

  # SUPER+G gaming keybind (hyprland.nix): evict the loaded model via
  # `ollama stop`, notify, write gaming state.
  aiWorkstationGamingStart = pkgs.writeShellScriptBin "ai-workstation-gaming-start" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.yq-go
        pkgs.ollama
        pkgs.systemd
      ]
    }:$PATH

    STATE_FILE=/run/ai-workstation/state.json

    if [ -f "$STATE_FILE" ]; then
      current_model=$(yq -r '.model' "$STATE_FILE" 2>/dev/null || echo null)
      if [ -n "$current_model" ] && [ "$current_model" != "null" ]; then
        ollama stop "$current_model" 2>/dev/null || true
      fi
    fi

    install -d -m 0755 /run/ai-workstation
    printf '{"state":"gaming","provider":null,"model":null,"updated":"%s"}\n' \
      "$(date -Iseconds)" > "$STATE_FILE"
    qubi-state-sync || true

    # Confines ollama.service to the 8 E-cores while gaming (AllowedCPUs=8-15,
    # confirmed via cpuinfo_max_freq) so the game keeps the P-cores. Runtime
    # set-property, self-heals if this script never runs again. Needs the
    # matching NOPASSWD sudo rule in ai-workstation.nix.
    sudo ${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota=700% AllowedCPUs=8-15 || \
      echo "[ai-workstation-gaming-start] cgroup cap failed (needs the ai-workstation.nix sudo rule + a switch) -- gaming proceeds without CPU/core isolation this time" >&2
  '';

  # Re-derives live eGPU state and calls the same NixOS sync services the
  # hotplug hooks use, rather than restoring a cached "previous" state
  # (stale if the user undocked mid-game).
  aiWorkstationGamingStop = pkgs.writeShellScriptBin "ai-workstation-gaming-stop" ''
    set -euo pipefail
    # pkgs.sudo is the non-setuid store binary; keeping it out of PATH lets
    # the inherited /run/wrappers/bin/sudo (the real wrapper) resolve.
    PATH=${lib.makeBinPath [ pkgs.pciutils ]}:$PATH

    # sudo's NOPASSWD rule matches the exact absolute systemctl path, not
    # the resolved binary -- bare `systemctl` fails the match and prompts.
    if lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      sudo ${pkgs.systemd}/bin/systemctl start ai-workstation-dock-sync.service
    else
      sudo ${pkgs.systemd}/bin/systemctl start ai-workstation-undock-sync.service
    fi

    # Empty values reset set-property's runtime override to the unit file's
    # own defaults.
    sudo ${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota= AllowedCPUs= || \
      echo "[ai-workstation-gaming-stop] cgroup restore failed (needs the ai-workstation.nix sudo rule + a switch)" >&2
  '';
in
{
  home.packages = [
    qubiStateSync
    aiWorkstationGamingStart
    aiWorkstationGamingStop
  ];
}
