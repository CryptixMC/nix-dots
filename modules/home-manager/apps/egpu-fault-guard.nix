{ pkgs, lib, ... }:

let
  # Follows the kernel log and, on the first eGPU fault line, stops the GPU
  # llama servers (--no-block: a unit stuck in D state must not hang us) and
  # notifies. It never kills, removes PCI devices or reboots; the fix is a reboot.
  guard = pkgs.writeShellScript "egpu-fault-guard" ''
    PATH=${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.systemd
        pkgs.libnotify
        pkgs.util-linux
      ]
    }

    PATTERNS=(
      'amdgpu.*page fault'
      'GCVM_L2_PROTECTION_FAULT'
      'ring .* timeout'
      'update PTE failed'
      'device lost'
      'pciehp: Slot\(.*\): Link Down'
      'Fatal error during GPU init'
      'amdgpu.*GPU reset'
    )
    UNITS=(qubi-llama-heavy.service qubi-llama-fast-gpu.service qubi-llama-light-gpu.service)
    DEBOUNCE=60
    last=0

    matches() {
      local p
      for p in "''${PATTERNS[@]}"; do
        printf '%s\n' "$1" | grep -Eq -- "$p" && return 0
      done
      return 1
    }

    handle() {
      local line=$1 now active=() u
      now=$(date +%s)
      (( now - last < DEBOUNCE )) && return 0
      last=$now
      for u in "''${UNITS[@]}"; do
        systemctl --user is-active --quiet "$u" && active+=("$u")
      done
      if [ -n "''${DRY_RUN:-}" ]; then
        echo "MATCH active=''${active[*]:-none}: $line"
        return 0
      fi
      if (( ''${#active[@]} > 0 )); then
        systemctl --user stop --no-block "''${UNITS[@]}"
        logger -t egpu-fault-guard "eGPU fault, stopping ''${active[*]}: $line"
        notify-send -u critical 'eGPU fault' "$line; GPU model servers stopped. Run qubi-health"
      else
        logger -t egpu-fault-guard "eGPU fault, no GPU unit active: $line"
        notify-send -u critical 'eGPU fault' "$line; no GPU model server was running. Run qubi-health"
      fi
    }

    # TEST_INPUT=1 reads lines from stdin instead of the kernel log.
    if [ -n "''${TEST_INPUT:-}" ]; then
      src() { cat; }
    else
      src() { journalctl -k -f -n 0 -o cat; }
    fi

    src | while IFS= read -r line; do
      matches "$line" && handle "$line"
    done
    exit 1
  '';
in
{
  systemd.user.services.egpu-fault-guard = {
    Unit = {
      Description = "Stop GPU llama servers on the first eGPU kernel fault";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 10;
    };
    Service = {
      ExecStart = "${guard}";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
