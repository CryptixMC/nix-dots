{ pkgs, lib, ... }:

let
  # Dock power button (17ef:a38f) sends USB Remote Wakeup, so every hub up
  # to the root needs power/wakeup=enabled. S5 wake also needs BIOS "Wake on USB".
  dockWakeupScript = pkgs.writeShellScript "dock-wakeup" ''
    sysfs="/sys$1"
    while [ -e "$sysfs" ]; do
      if [ -f "$sysfs/power/wakeup" ]; then
        echo enabled > "$sysfs/power/wakeup" 2>/dev/null || true
      fi
      bn=$(basename "$sysfs")
      parent=$(dirname "$sysfs")
      [ "$parent" = "$sysfs" ] && break
      sysfs="$parent"
      case "$bn" in usb*) break ;; esac
    done
  '';

  # The dock's r8152 sometimes negotiates 100 Mbps; a clean autoneg restart recovers Gigabit.
  ethGigabitFixScript = pkgs.writeShellScript "eth-gigabit-fix" ''
    PATH=${lib.makeBinPath [ pkgs.ethtool ]}:$PATH
    iface="$1"
    ethtool -s "$iface" autoneg off
    ethtool -s "$iface" speed 1000 duplex full autoneg on
  '';

  # eGPU BAR 0 (256MB) comes up at 0x0: the inner TB bridge (51:01.0) gets a
  # tiny window and hotplug never redistributes the outer bridge's (50:00.0)
  # spare space. Removing the inner bridges and rescanning from 50:00.0 fixes it.
  egpuBarFixScript = pkgs.writeShellScript "egpu-bar-fix" ''
    PATH=${
      lib.makeBinPath [
        pkgs.pciutils
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnused
        pkgs.util-linux
        pkgs.kmod
        pkgs.systemd
      ]
    }:$PATH

    log() { echo "[egpu-bar-fix] $*"; logger -t egpu-bar-fix "$*"; }

    # Wait for the TB hotplug / PCIe enumeration to settle.
    sleep 4

    # Locate the RX 6800 XT by vendor:device (1002:73bf = Navi 21).
    GPU_SYS=""
    for d in /sys/bus/pci/devices/0000:*; do
      [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1002" ] || continue
      [ "$(cat "$d/device" 2>/dev/null)" = "0x73bf" ] || continue
      GPU_SYS="$d"
      break
    done

    if [ -z "$GPU_SYS" ]; then
      log "RX 6800 XT not found on PCI bus — eGPU not connected?"
      exit 0
    fi

    BAR0=$(awk 'NR==1{print $1}' "$GPU_SYS/resource" 2>/dev/null)
    if [ "$BAR0" != "0x0000000000000000" ]; then
      log "BAR 0 already assigned at $BAR0 — nothing to do"
      exit 0
    fi

    log "BAR 0 stuck at 0x0; attempting bridge window reallocation..."

    # Topology: 50:00.0 -> 51:01.0 -> 52:00.0 -> 53:00.0 -> 54:00.0 (GPU).
    GPU_BDF=$(basename "$GPU_SYS")            # e.g. 0000:54:00.0
    GPU_BUS=$(echo "$GPU_BDF" | cut -d: -f2)  # e.g. 54 (hex sysfs notation)

    OUTER_SEC=$(setpci -s 50:00.0 SECONDARY_BUS.B 2>/dev/null)
    OUTER_SEC=$(printf '%02x' "0x$OUTER_SEC" 2>/dev/null)

    # Walk up from the GPU bus to the bridge sitting on OUTER_SEC.
    TARGET_BRIDGE=""
    CUR_BUS="$GPU_BUS"

    for _i in 1 2 3 4 5; do
      for dev in /sys/bus/pci/devices/0000:*; do
        bdf=$(basename "$dev" | sed 's/0000://')
        sec=$(setpci -s "$bdf" SECONDARY_BUS.B 2>/dev/null) || continue
        sec=$(printf '%02x' "0x$sec" 2>/dev/null) || continue
        if [ "$sec" = "$CUR_BUS" ]; then
          pri=$(setpci -s "$bdf" PRIMARY_BUS.B 2>/dev/null)
          pri=$(printf '%02x' "0x$pri" 2>/dev/null) || continue
          if [ "$pri" = "$OUTER_SEC" ]; then
            TARGET_BRIDGE="$dev"
            break 2
          fi
          CUR_BUS="$pri"
          break
        fi
      done
    done

    if [ -z "$TARGET_BRIDGE" ]; then
      # Fallback: the inner bridge is always 51:01.0 on this machine.
      [ -e /sys/bus/pci/devices/0000:51:01.0 ] && TARGET_BRIDGE=/sys/bus/pci/devices/0000:51:01.0
    fi

    if [ -z "$TARGET_BRIDGE" ]; then
      log "Could not locate inner TB bridge — giving up"
      exit 1
    fi

    log "Removing ALL inner TB bridges under 50:00.0 and rescanning clean"

    # Unbind amdgpu first to avoid kernel warnings on device removal.
    if [ -e "$GPU_SYS/driver" ]; then
      echo "$(basename "$GPU_SYS")" > "$GPU_SYS/driver/unbind" 2>/dev/null || true
    fi

    # Remove all bridges on OUTER_SEC so the rescan allocates from a clean slate.
    for dev in /sys/bus/pci/devices/0000:*; do
      bdf=$(basename "$dev" | sed 's/0000://')
      pri=$(setpci -s "$bdf" PRIMARY_BUS.B 2>/dev/null) || continue
      pri=$(printf '%02x' "0x$pri" 2>/dev/null) || continue
      if [ "$pri" = "$OUTER_SEC" ]; then
        log "Removing bridge $bdf (primary=$pri)"
        echo 1 > "$dev/remove" 2>/dev/null || true
      fi
    done
    sleep 1

    echo 1 > /sys/bus/pci/devices/0000:50:00.0/rescan
    sleep 3

    for d in /sys/bus/pci/devices/0000:*; do
      [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1002" ] || continue
      [ "$(cat "$d/device" 2>/dev/null)" = "0x73bf" ] || continue
      BAR0=$(awk 'NR==1{print $1}' "$d/resource" 2>/dev/null)
      log "After realloc: GPU at $(basename "$d"), BAR 0 = $BAR0"
      if [ "$BAR0" != "0x0000000000000000" ]; then
        log "Success — triggering driver bind"
        echo "$(basename "$d")" > /sys/bus/pci/drivers/amdgpu/bind 2>/dev/null || true
        # kanshi may still be stopped from the last eject. Don't restart ollama
        # here: qubi-gpu-attach does, and doing both races two restarts.
        runuser -u cryptix -- env XDG_RUNTIME_DIR="/run/user/$(id -u cryptix)" systemctl --user restart kanshi.service 2>/dev/null || true
        # Fire-and-forget so a Qubi failure can't fail the BAR fix.
        systemctl start qubi-gpu-attach.service --no-block 2>/dev/null || true
      else
        log "BAR 0 still 0x0 — manual intervention needed"
      fi
    done
  '';

  # Detach the eGPU before unplug: amdgpu teardown must run against live
  # hardware or Hyprland wedges on a black screen. Triggered by SUPER+SHIFT+U,
  # or best-effort by udev on TB removal.
  egpuEjectScript = pkgs.writeShellScript "egpu-eject" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnused
        pkgs.util-linux
        pkgs.systemd
        pkgs.hyprland
        pkgs.procps
      ]
    }:$PATH

    log() { echo "[egpu-eject] $*"; logger -t egpu-eject "$*"; }

    exec 9>/run/lock/egpu-eject.lock
    flock -n 9 || { log "an eject is already in progress — skipping"; exit 0; }

    RUNTIME_DIR="/run/user/$(id -u cryptix)"
    HYPR_SIG=$(ls -t "$RUNTIME_DIR/hypr" 2>/dev/null | head -n1)

    as_user() {
      runuser -u cryptix -- env XDG_RUNTIME_DIR="$RUNTIME_DIR" "$@"
    }
    hyprctl_user() {
      as_user env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" hyprctl "$@" 2>/dev/null || true
    }

    # Stage 0: locate the RX 6800 XT; nothing to do if it isn't present.
    GPU_SYS=""
    for d in /sys/bus/pci/devices/0000:*; do
      [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1002" ] || continue
      [ "$(cat "$d/device" 2>/dev/null)" = "0x73bf" ] || continue
      GPU_SYS="$d"
      break
    done

    if [ -z "$GPU_SYS" ]; then
      log "eGPU not present — nothing to eject"
      exit 0
    fi

    ok=1

    # Stop ollama so ROCm releases its DRM handles before unbind.
    log "stopping ollama.service"
    systemctl start qubi-gpu-release.service 2>/dev/null || true

    # A running game's Vulkan DRM context can also hang the unbind; abort rather than kill it.
    if pgrep -x gamescope >/dev/null 2>&1; then
      log "gamescope is running — refusing to eject until it's closed"
      hyprctl_user notify -1 8000 "rgb(f9e2af)" "Quit your game first, then retry SUPER+SHIFT+U"
      exit 1
    fi

    # Stop kanshi (it would re-enable the eGPU outputs) and re-enable eDP-1,
    # which the "docked" profile disabled, or no output is left on.
    log "stopping kanshi, disabling eGPU-attached outputs, enabling eDP-1"
    as_user systemctl --user stop kanshi.service 2>/dev/null || true
    hyprctl_user keyword monitor DP-6,disable
    hyprctl_user keyword monitor HDMI-A-2,disable
    hyprctl_user keyword monitor eDP-1,preferred,auto,1

    # Unbind amdgpu while the link is still live, with its consumers already gone.
    GPU_BDF=$(basename "$GPU_SYS")
    if [ -e "$GPU_SYS/driver" ]; then
      log "unbinding amdgpu from $GPU_BDF"
      if ! timeout 5 sh -c "echo '$GPU_BDF' > '$GPU_SYS/driver/unbind'" 2>/dev/null; then
        log "amdgpu unbind timed out — do NOT unplug, check journalctl -k"
        ok=0
      fi
    else
      log "amdgpu already unbound from $GPU_BDF"
    fi

    # Deauthorize the TB tunnel; safe only after amdgpu is unbound.
    if [ "$ok" = "1" ]; then
      TB_DEV=""
      for d in /sys/bus/thunderbolt/devices/*; do
        [ -f "$d/unique_id" ] || continue
        [ "$(cat "$d/unique_id" 2>/dev/null)" = "b9010000-0062-640e-83f2-8ddd4a93f908" ] || continue
        TB_DEV="$d"
        break
      done

      if [ -n "$TB_DEV" ]; then
        if [ "$(cat "$TB_DEV/authorized" 2>/dev/null)" = "0" ]; then
          log "Thunderbolt tunnel already deauthorized"
        elif timeout 5 sh -c "echo 0 > '$TB_DEV/authorized'" 2>/dev/null; then
          log "Thunderbolt tunnel deauthorized"
        else
          log "failed to deauthorize Thunderbolt tunnel — do NOT unplug"
          ok=0
        fi
      else
        log "Thunderbolt device node not found — do NOT unplug"
        ok=0
      fi
    fi

    # Restart ollama CPU-only. Skipped on failure: a half-detached GPU with dead
    # KFD makes ollama-rocm hang in D-state (see the egpu-dock-undock skill).
    if [ "$ok" = "1" ]; then
      log "restarting ollama.service (CPU-only while undocked)"
      systemctl restart ollama.service 2>/dev/null || true
    else
      log "eject failed — leaving ollama.service stopped rather than risking a wedged runner on a half-detached GPU"
    fi

    # Notify last so "safe to unplug" is only shown on success.
    if [ "$ok" = "1" ]; then
      hyprctl_user notify -1 5000 "rgb(a6e3a1)" "eGPU deauthorized — safe to unplug"
    else
      hyprctl_user notify -1 8000 "rgb(f38ba8)" "eGPU eject failed — do NOT unplug, qubi's local models stay offline, check journalctl -t egpu-eject"
    fi
  '';

  # Full CPU+GPU performance while docked; opportunistic clocking starves the
  # GPU waiting on CPU-submitted work. Undocked use still power-saves.
  egpuPerfOnScript = pkgs.writeShellScript "egpu-perf-on" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ]
    }:$PATH
    log() { echo "[egpu-perf-on] $*"; logger -t egpu-perf-on "$*"; }

    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo performance > "$gov" 2>/dev/null || true
    done
    log "CPU governor -> performance"

    # The DPM node only exists once amdgpu is bound; poll briefly.
    DPM=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      for d in /sys/bus/pci/devices/0000:*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1002" ] || continue
        [ "$(cat "$d/device" 2>/dev/null)" = "0x73bf" ] || continue
        [ -e "$d/power_dpm_force_performance_level" ] || continue
        DPM="$d/power_dpm_force_performance_level"
        break 2
      done
      sleep 1
    done

    if [ -n "$DPM" ]; then
      echo high > "$DPM" 2>/dev/null || true
      log "GPU power_dpm_force_performance_level -> high"
    else
      log "amdgpu DPM sysfs not found after 10s -- GPU still powering up?"
    fi
  '';

  # Reverts egpuPerfOnScript when the eGPU detaches.
  egpuPerfOffScript = pkgs.writeShellScript "egpu-perf-off" ''
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.util-linux
      ]
    }:$PATH
    log() { echo "[egpu-perf-off] $*"; logger -t egpu-perf-off "$*"; }

    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo powersave > "$gov" 2>/dev/null || true
    done
    log "CPU governor -> powersave"

    for d in /sys/bus/pci/devices/0000:*; do
      [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1002" ] || continue
      [ "$(cat "$d/device" 2>/dev/null)" = "0x73bf" ] || continue
      [ -e "$d/power_dpm_force_performance_level" ] || continue
      echo auto > "$d/power_dpm_force_performance_level" 2>/dev/null || true
      log "GPU power_dpm_force_performance_level -> auto"
    done
  '';
in
{
  # ThinkPad T14 (Intel) + AMD RX 6800 XT via Thunderbolt eGPU

  hardware.enableRedistributableFirmware = true;

  # --- Thunderbolt ---
  # Load the TB controller in initrd so authorization fires before userspace.
  boot.initrd.kernelModules = [ "thunderbolt" ];

  # boltd requires imperative enrollment (boltctl enroll) or it silently
  # blocks authorization; use a udev rule instead and leave the daemon off.
  services.hardware.bolt.enable = false;

  # Cabling: plug the dock into the laptop's other TB4 port, not the eGPU
  # enclosure's passthrough, which shares PCIe bandwidth with the GPU tunnel.

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="b9010000-0062-640e-83f2-8ddd4a93f908", ATTR{authorized}="1"
    # When the RX 6800 XT appears on the PCIe bus, start the BAR-fix service.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x73bf", TAG+="systemd", ENV{SYSTEMD_WANTS}="egpu-bar-fix.service"
    # Surprise-unplug backstop. Matches TB remove, not PCI remove, since the
    # PCI uevent only fires after amdgpu's .remove() returns, which is what hangs.
    ACTION=="remove", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="b9010000-0062-640e-83f2-8ddd4a93f908", TAG+="systemd", ENV{SYSTEMD_WANTS}="egpu-eject.service"
    # Enable USB wakeup chain for ThinkPad USB-C Dock Gen2 power button.
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="17ef", ATTRS{idProduct}=="a38f", RUN+="${dockWakeupScript} $env{DEVPATH}"
    # See ethGigabitFixScript.
    ACTION=="add", SUBSYSTEM=="net", DRIVERS=="r8152", RUN+="${ethGigabitFixScript} $env{INTERFACE}"
    # Autosuspend on the dock's Ethernet causes carrier drops.
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="17ef", ATTRS{idProduct}=="a387", ATTR{power/control}="on"
  '';

  # --- AMD GPU ---
  # Don't load amdgpu in initrd — the GPU doesn't exist until TB auth completes.
  hardware.amdgpu.initrd.enable = false;
  # Pre-load the driver so it binds the moment the PCIe device appears.
  boot.kernelModules = [ "amdgpu" ];

  # Pinned to the kernel the eGPU workarounds were validated on; re-validate
  # the eGPU checklist before bumping.
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  # --- Kernel Parameters ---
  boot.kernelParams = [
    # With the BIOS "512MB graphics memory" setting, gives BAR 0 enough window.
    "pci=realloc,nocrs"

    # Release the EFI framebuffer so amdgpu can own the display output.
    "video=efifb:off"

    # Thunderbolt bridges don't handle ASPM reliably — disable it.
    "pcie_aspm=off"

    # ThinkPad Thunderbolt handshake fails with IOMMU on.
    "intel_iommu=off"

    # Runtime PM will lose the Thunderbolt link on GPU sleep.
    "amdgpu.runpm=0"

    # DPIA link training retries forever with no monitor at init (6.18+).
    "amdgpu.dcdebugmask=0x400"
    "amdgpu.sg_display=0"

    # Native PCIe hotplug is required to see the GPU after TB auth.
    "pcie_ports=native"

    # amdgpu's internal ASPM (separate from global pcie_aspm=off) floods
    # AER errors under load on TB-tunneled GPUs; disable both.
    "amdgpu.aspm=0"
    "pcie_port_pm=off"

    # The thunderbolt driver has no AER recovery callback, so an uncorrectable
    # error on the tunnel hangs the system. Link-level retry still works without AER.
    "pci=noaer"
  ];

  # Silences "cannot get freq at ep 0x86" from the dock's USB audio.
  boot.extraModprobeConfig = ''
    options snd-usb-audio implicit_fb=1
  '';

  # --- Graphics ---
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      rocmPackages.clr.icd
    ];
  };

  services.xserver.videoDrivers = [
    "amdgpu"
    "modesetting"
  ];

  # --- BAR Reallocation Service ---
  # Started by udev when the GPU appears.
  systemd.services.egpu-bar-fix = {
    description = "Fix AMD eGPU PCIe BAR 0 allocation via bridge window expansion";
    after = [ "sysinit.target" ];
    wants = [ "egpu-perf-on.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = egpuBarFixScript;
    };
  };

  # --- Safe Eject Service ---
  systemd.services.egpu-eject = {
    description = "Gracefully detach the AMD eGPU before Thunderbolt disconnection";
    wants = [ "egpu-perf-off.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = egpuEjectScript;
    };
  };

  # --- eGPU-gated performance toggle ---
  # Pulled in via `wants` from the bar-fix and eject services.
  systemd.services.egpu-perf-on = {
    description = "Force CPU governor=performance and GPU DPM=high while the eGPU is docked";
    after = [ "egpu-bar-fix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = egpuPerfOnScript;
    };
  };

  systemd.services.egpu-perf-off = {
    description = "Revert CPU governor and GPU DPM to power-saving defaults when the eGPU detaches";
    before = [ "egpu-eject.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = egpuPerfOffScript;
    };
  };

  # Passwordless for the eject keybind; scoped to exactly this command.
  security.sudo.extraRules = [
    {
      users = [ "cryptix" ];
      commands = [
        {
          command = "${pkgs.systemd}/bin/systemctl start egpu-eject.service";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # --- Packages ---
  environment.systemPackages = with pkgs; [
    radeontop
    corectrl
    vulkan-tools
    pciutils
    clinfo
    ethtool
  ];
}
