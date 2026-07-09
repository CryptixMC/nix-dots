{ pkgs, lib, ... }:

let
  # The ThinkPad USB-C Dock Gen 2 power button (Cypress 17ef:a38f) sends a
  # USB Remote Wakeup signal — not a keypress — to wake the system from S3.
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

  # When the AMD GPU appears via Thunderbolt PCIe tunneling, its BAR 0
  # (256MB VRAM aperture) is stuck at address 0x0 because the inner TB
  # bridge (51:01.0) was given only a 3MB prefetchable window at enumeration
  # time. This script removes the inner bridges and rescans from 50:00.0 cleanly.
  egpuBarFixScript = pkgs.writeShellScript "egpu-bar-fix" ''
    PATH=${
      lib.makeBinPath [
        pkgs.pciutils
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnused
        pkgs.util-linux
        pkgs.kmod
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

    GPU_BDF=$(basename "$GPU_SYS")
    GPU_BUS=$(echo "$GPU_BDF" | cut -d: -f2)

    OUTER_SEC=$(setpci -s 50:00.0 SECONDARY_BUS.B 2>/dev/null)
    OUTER_SEC=$(printf '%02x' "0x$OUTER_SEC" 2>/dev/null)

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
      [ -e /sys/bus/pci/devices/0000:51:01.0 ] && TARGET_BRIDGE=/sys/bus/pci/devices/0000:51:01.0
    fi

    if [ -z "$TARGET_BRIDGE" ]; then
      log "Could not locate inner TB bridge — giving up"
      exit 1
    fi

    log "Removing ALL inner TB bridges under 50:00.0 and rescanning clean"

    if [ -e "$GPU_SYS/driver" ]; then
      echo "$(basename "$GPU_SYS")" > "$GPU_SYS/driver/unbind" 2>/dev/null || true
    fi

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
      else
        log "BAR 0 still 0x0 — manual intervention needed"
      fi
    done
  '';
in
{
  # ThinkPad T14 (Intel) + AMD RX 6800 XT via Thunderbolt eGPU
  hardware.enableRedistributableFirmware = true;

  # --- Thunderbolt ---
  boot.initrd.kernelModules = [ "thunderbolt" ];
  services.hardware.bolt.enable = false;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="b9010000-0062-640e-83f2-8ddd4a93f908", ATTR{authorized}="1"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x73bf", TAG+="systemd", ENV{SYSTEMD_WANTS}="egpu-bar-fix.service"
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="17ef", ATTRS{idProduct}=="a38f", RUN+="${dockWakeupScript} $env{DEVPATH}"
  '';

  # --- AMD GPU ---
  hardware.amdgpu.initrd.enable = false;
  boot.kernelModules = [ "amdgpu" ];

  # --- Kernel Parameters ---
  boot.kernelParams = [
    # Allow kernel reallocations but drop conflicting 'nocrs'
    "pci=realloc"
    "video=efifb:off"
    "pcie_aspm=off"

    # Fix for Minecraft/eGPU Access Violations:
    "intel_iommu=on"
    "iommu=pt"
    "pci=noaer"

    "amdgpu.runpm=0"
    "amdgpu.dcdebugmask=0x400"
    "amdgpu.sg_display=0"
    "pcie_ports=native"
    "root=fstab"
  ];

  # --- Systemd Service configuration for the BAR script ---
  systemd.services.egpu-bar-fix = {
    description = "Fix AMD eGPU BAR 0 Windows";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${egpuBarFixScript}";
    };
  };
}
