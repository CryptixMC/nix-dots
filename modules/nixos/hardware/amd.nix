{ pkgs, ... }:

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
  '';

  # --- AMD GPU ---
  # Don't load amdgpu in initrd — the GPU doesn't exist until TB auth completes.
  hardware.amdgpu.initrd.enable = false;
  # Pre-load the driver so it binds the moment the PCIe device appears.
  boot.kernelModules = [ "amdgpu" ];

  # --- Kernel Parameters ---
  boot.kernelParams = [
    # Thunderbolt bridge window must fit the 6800 XT's BAR (16GB VRAM w/ ReBAR).
    # nocrs lets the kernel override the BIOS's 448MB cap; without it hpmemsize
    # is silently ignored and the GPU can't enumerate because the window is too small.
    "pci=realloc,hpmemsize=32G,hpiosize=512M,nocrs"

    # Release the EFI framebuffer so amdgpu can own the display output.
    "video=efifb:off"

    # Thunderbolt bridges don't handle ASPM reliably — disable it.
    "pcie_aspm=off"

    # ThinkPad Thunderbolt handshake fails with IOMMU on.
    "intel_iommu=off"

    # Runtime PM will lose the Thunderbolt link on GPU sleep.
    "amdgpu.runpm=0"

    # The DC stack retries DPIA (TB DisplayPort) link training indefinitely when
    # no monitor is attached at init, causing a hang. 0x10 fixed this in older
    # kernels but the bit shifted in 6.18 — 0x400 is the next candidate.
    "amdgpu.dcdebugmask=0x400"
    "amdgpu.sg_display=0"

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

  # --- Packages ---
  environment.systemPackages = with pkgs; [
    radeontop
    corectrl
    vulkan-tools
    pciutils
    clinfo
  ];
}
