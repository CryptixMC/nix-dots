{ pkgs, lib, ... }:

let
  # Read-only advisory check for the known post-crash dead-KFD state
  # documented in TODO.md §7 ("Found and fixed along the way" under Phase
  # 1a): a crashed/surprise eGPU removal can leave the amdgpu driver cleanly
  # bound with a valid PCI BAR while ROCm/KFD compute is silently dead
  # (`rocminfo` reports zero GPU agents). Nothing else in this repo detects
  # that state proactively today — it was only ever noticed by hand. This
  # timer exists purely to surface it faster; it must never act on it, since
  # the only known fix is a full reboot (also documented in TODO.md), not
  # anything this script could safely automate.
  checkScript = pkgs.writeShellScript "qubi-health-check" ''
    PATH=${
      lib.makeBinPath [
        pkgs.pciutils
        pkgs.rocmPackages.rocminfo
        pkgs.coreutils
        pkgs.util-linux
        pkgs.hyprland
        pkgs.gnugrep
      ]
    }:$PATH

    log() { echo "[qubi-health] $*"; logger -t qubi-health "$*"; }

    RUNTIME_DIR="/run/user/$(id -u cryptix)"
    HYPR_SIG=$(ls -t "$RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
    hyprctl_user() {
      runuser -u cryptix -- env XDG_RUNTIME_DIR="$RUNTIME_DIR" HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" hyprctl "$@" 2>/dev/null || true
    }

    if ! lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      log "eGPU not present on PCI bus — nothing to check"
      exit 0
    fi

    gpu_agents=$(rocminfo 2>/dev/null | grep -c "Device Type:.*GPU")

    if [ "$gpu_agents" -eq 0 ]; then
      log "MISMATCH: eGPU present on PCI bus but rocminfo reports zero GPU agents — likely dead-KFD state, reboot required to clear (see TODO.md §7)"
      hyprctl_user notify -1 15000 "rgb(f38ba8)" "eGPU: dead ROCm/KFD state detected (GPU present, 0 compute agents) — reboot needed"
    else
      log "OK: eGPU present, $gpu_agents GPU agent(s) reported by rocminfo"
    fi
  '';
in
{
  systemd.services.qubi-health = {
    description = "Advisory check: eGPU PCI presence vs. live ROCm/KFD agent count";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = checkScript;
    };
  };

  systemd.timers.qubi-health = {
    description = "Run qubi-health every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Unit = "qubi-health.service";
    };
  };
}
