{ pkgs, lib, ... }:

let
  # The ThinkPad USB-C Dock Gen 2 power button (Cypress 17ef:a38f) sends a
  # USB Remote Wakeup signal — not a keypress — to wake the system from S3.
  # For that signal to reach the ThinkPad, every hub and the root USB
  # controller in the chain must have power/wakeup = "enabled".
  # This script walks up the sysfs parent chain from the dock button device
  # and enables wakeup on each node up to and including the root hub (usb*).
  # NOTE: wake from S5 (powered-off) requires a BIOS "Wake on USB" setting.
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
  # time.  The outer TB bridge (50:00.0) has 482MB available, but the
  # hotplug path never redistributes that space to inner bridges.
  #
  # Fix: once the GPU device appears (with BAR 0 = 0x0), remove the inner
  # bridge that contains it and rescan from the outer bridge.  The kernel
  # allocator then sees 482MB of free prefetchable space and gives the inner
  # bridge the 258MB it needs for BAR 0 + overhead.
  egpuBarFixScript = pkgs.writeShellScript "egpu-bar-fix" ''
    PATH=${lib.makeBinPath [ pkgs.pciutils pkgs.coreutils pkgs.gawk pkgs.gnused pkgs.util-linux pkgs.kmod ]}:$PATH

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

    # Walk up: GPU bus → find the bridge that is a direct child of 50:00.0.
    # Topology: 50:00.0 → 51:01.0 → 52:00.0 → 53:00.0 → 54:00.0 (GPU)
    # 50:00.0's SECONDARY bus is 51, so we want the bridge whose PRIMARY = 51.
    GPU_BDF=$(basename "$GPU_SYS")            # e.g. 0000:54:00.0
    GPU_BUS=$(echo "$GPU_BDF" | cut -d: -f2)  # e.g. 54 (hex sysfs notation)

    # Get 50:00.0's secondary bus number (the bus directly under it).
    OUTER_SEC=$(setpci -s 50:00.0 SECONDARY_BUS.B 2>/dev/null)
    OUTER_SEC=$(printf '%02x' "0x$OUTER_SEC" 2>/dev/null)

    # Walk up from GPU bus until we find the bridge sitting on OUTER_SEC.
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
          # Stop when this bridge's primary bus is 50:00.0's secondary bus.
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

    # Remove every bridge whose primary bus is 50:00.0's secondary bus.
    # This lets the kernel allocate all three bridges from a clean slate,
    # which means it can place the 256MB GPU BAR at the 256MB-aligned base
    # of 50:00.0's window without interference from pre-existing allocations.
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

    # Report result.
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
  # Load the TB controller in initrd so authorization fires before userspace.
  boot.initrd.kernelModules = [ "thunderbolt" ];

  # boltd requires the device to be enrolled imperatively (boltctl enroll).
  # Without enrollment boltd silently blocks authorization, so use a udev
  # rule instead and leave the daemon off.
  services.hardware.bolt.enable = false;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{unique_id}=="b9010000-0062-640e-83f2-8ddd4a93f908", ATTR{authorized}="1"
    # When the RX 6800 XT appears on the PCIe bus, start the BAR-fix service.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1002", ATTR{device}=="0x73bf", TAG+="systemd", ENV{SYSTEMD_WANTS}="egpu-bar-fix.service"
    # Enable USB wakeup chain for ThinkPad USB-C Dock Gen2 power button.
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="17ef", ATTRS{idProduct}=="a38f", RUN+="${dockWakeupScript} $env{DEVPATH}"
  '';

  # --- AMD GPU ---
  # Don't load amdgpu in initrd — the GPU doesn't exist until TB auth completes.
  hardware.amdgpu.initrd.enable = false;
  # Pre-load the driver so it binds the moment the PCIe device appears.
  boot.kernelModules = [ "amdgpu" ];

  # --- Kernel Parameters ---
  boot.kernelParams = [
    # Allow the kernel to reallocate PCI bridge windows for hot-plugged devices.
    # Combined with the BIOS "512MB graphics memory" setting (which tells the
    # Thunderbolt firmware to program larger bridge apertures), this should give
    # the RX 6800 XT enough prefetchable window for its 256MB BAR 0.
    "pci=realloc,nocrs"

    # Release the EFI framebuffer so amdgpu can own the display output.
    "video=efifb:off"

    # Thunderbolt bridges don't handle ASPM reliably — disable it.
    "pcie_aspm=off"

    # ThinkPad Thunderbolt handshake fails with IOMMU on.
    "intel_iommu=off"

    # Runtime PM will lose the Thunderbolt link on GPU sleep.
    "amdgpu.runpm=0"

    # Enable kernel-native PCIe hotplug instead of ACPI-managed.
    # Required for the kernel to detect the GPU on the PCIe bus after TB auth.
    "pcie_ports=native"
  ];

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

  services.xserver.videoDrivers = [ "amdgpu" "modesetting" ];

  # --- BAR Reallocation Service ---
  # Triggered by udev when the GPU appears; expands the inner TB bridge window
  # so amdgpu can map BAR 0 (256MB VRAM aperture).
  systemd.services.egpu-bar-fix = {
    description = "Fix AMD eGPU PCIe BAR 0 allocation via bridge window expansion";
    # Don't auto-start at boot; only fires when udev raises the GPU add event.
    # We still set wants/after so it runs at the right point if triggered early.
    after = [ "sysinit.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = egpuBarFixScript;
    };
  };

  # --- Packages ---
  environment.systemPackages = with pkgs; [
    radeontop
    corectrl
    vulkan-tools
    pciutils
    clinfo
  ];
}
