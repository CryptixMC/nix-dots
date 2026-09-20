{ pkgs, lib, ... }:

let
  scriptWithPath = import ../../../lib/scriptWithPath.nix { inherit lib pkgs; };
  mkUserScript = import ../../../lib/mkUserScript.nix;

  # Shared status-computation logic, used by both the CLI (qubi-health, run
  # by hand) and the advisory timer below (which just parses this CLI's
  # first output line rather than re-implementing the checks). Read-only —
  # must never act on what it finds, since the only known fix for either bad
  # state is a full reboot (see TODO.md §7), not anything scriptable here.
  #
  # Priority order matters: dead-KFD is checked before the wedged-runner
  # scan because a wedged `llama-server` is *expected* collateral of a dead
  # KFD state (same root cause, see TODO.md §7 "Phase 1a — Found and fixed
  # along the way") — reporting DEAD-KFD-REBOOT-REQUIRED is the more useful
  # signal than WEDGED-RUNNER when both are simultaneously true.
  healthCli = pkgs.writeShellScriptBin "qubi-health" ''
    set -uo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.pciutils
        pkgs.rocmPackages.rocminfo
        pkgs.coreutils
        pkgs.procps
        pkgs.gnugrep
      ]
    }:$PATH

    if ! lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      echo "EGPU-ABSENT"
      exit 0
    fi

    gpu_agents=$(rocminfo 2>/dev/null | grep -c "Device Type:.*GPU")
    if [ "''${gpu_agents:-0}" -eq 0 ]; then
      echo "DEAD-KFD-REBOOT-REQUIRED"
      exit 0
    fi

    # A `llama-server` (Ollama's runner) stuck in D (uninterruptible sleep)
    # state is the unkillable-orphan symptom documented in TODO.md §7 — the
    # kernel is waiting on hardware that's gone, survives `systemctl
    # restart`/`stop` of ollama.service itself. `ps -eo stat,comm` is enough;
    # no need for the full cmdline.
    if ps -eo stat,comm 2>/dev/null | grep -E '^D' | grep -q 'llama-server'; then
      echo "WEDGED-RUNNER"
      exit 0
    fi

    echo "HEALTHY ($gpu_agents GPU agent(s))"
  '';

  # Advisory-only wrapper: runs the CLI above, notifies on the two bad
  # states, stays silent (just logs) on HEALTHY/EGPU-ABSENT since those are
  # both normal, common conditions not worth a desktop popup every 5 minutes.
  checkScript = scriptWithPath {
    name = "qubi-health-check";
    runtimeInputs = [
      healthCli
      pkgs.util-linux
      pkgs.hyprland
      pkgs.coreutils
    ];
    text = ''
      log() { echo "[qubi-health] $*"; logger -t qubi-health "$*"; }

      ${mkUserScript { user = "cryptix"; }}
      HYPR_SIG=$(ls -t "$RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
      hyprctl_user() {
        as_user env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" hyprctl "$@" 2>/dev/null || true
      }

      status=$(qubi-health)
      log "$status"

      case "$status" in
        DEAD-KFD-REBOOT-REQUIRED*)
          hyprctl_user notify -1 15000 "rgb(f38ba8)" "eGPU: dead ROCm/KFD state detected (GPU present, 0 compute agents) — reboot needed"
          ;;
        WEDGED-RUNNER*)
          hyprctl_user notify -1 15000 "rgb(f38ba8)" "Ollama: llama-server stuck in D-state (unkillable) — reboot needed to clear"
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ healthCli ];

  systemd.services.qubi-health = {
    description = "Advisory check: eGPU PCI presence vs. live ROCm/KFD agent count, plus wedged-runner detection";
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
