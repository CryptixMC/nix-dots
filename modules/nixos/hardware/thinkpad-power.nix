{ pkgs, ... }:
let
  # This chassis's BIOS/EC ships an unmanaged PL1 = 64W with a near-infinite
  # (127.9s) time window -- i.e. "sustained 64W forever" -- instead of the
  # i7-1260P's stock PL1 = 28W/PL2 = 64W(short). Confirmed via
  # /sys/class/powercap/intel-rapl/intel-rapl:0/constraint_*_power_limit_uw
  # and by package_throttle_count climbing continuously (~3.2k events/13.5s
  # in one ARC Raiders session) while package temp stayed at 74C even 6
  # minutes after the game exited -- classic sustained heat-soak, not a
  # transient spike. This isn't fixable via ACPI platform_profile (already
  # "balanced", not "performance") -- the firmware's own default is
  # miscalibrated for what this chassis can actually cool.
  #
  # `throttled` (erpalma/throttled, packaged as pkgs.throttled) is the
  # standard community fix for this exact class of Lenovo bug: it writes
  # PL1/PL2 directly via MSR + MCHBAR MMIO on a repeating timer, because the
  # EC resets those registers on its own cadence (~5s on AC, ~30s on
  # battery) -- a one-shot fix does not stick.
  #
  # Numbers below are a conservative starting point, NOT a final tuned
  # value -- see README.md for the tuning method (watch
  # package_throttle_count / _total_time_ms deltas and package temp during
  # a play session with MangoHud running, adjust PL1_Tdp_W up if temps stay
  # well under Trip_Temp_C, down if throttle events keep accruing).
  throttledConf = pkgs.writeText "throttled.conf" ''
    [GENERAL]
    Enabled: True
    Sysfs_Power_Path: /sys/class/power_supply/AC*/online
    Autoreload: True

    # AC profile: sized for what a T14 Gen 3's cooling can realistically
    # sustain -- well below the BIOS's unmanaged 64W, with ~25% headroom
    # over the stock 28W PL1 base. PL1_Duration_s=28 matches Intel's spec
    # tau; PL2 stays near-instant (2ms) so short bursts still turbo.
    [AC]
    Update_Rate_s: 5
    PL1_Tdp_W: 35
    PL1_Duration_s: 28
    PL2_Tdp_W: 54
    PL2_Duration_S: 0.002
    Trip_Temp_C: 90
    cTDP: 0
    Disable_BDPROCHOT: False

    # Battery profile: not this change's focus (gaming sessions are on AC)
    # -- left close to throttled's own stock defaults, just slightly lower
    # to match this chassis.
    [BATTERY]
    Update_Rate_s: 30
    PL1_Tdp_W: 20
    PL1_Duration_s: 28
    PL2_Tdp_W: 35
    PL2_Duration_S: 0.002
    Trip_Temp_C: 80
    cTDP: 0
    Disable_BDPROCHOT: False

    # No undervolt -- separate risk/tuning axis, out of scope here.
    [UNDERVOLT.AC]
    CORE: 0
    GPU: 0
    CACHE: 0
    UNCORE: 0
    ANALOGIO: 0

    [UNDERVOLT.BATTERY]
    CORE: 0
    GPU: 0
    CACHE: 0
    UNCORE: 0
    ANALOGIO: 0
  '';
in
{
  # `throttled` writes MSRs directly, which requires the `msr` module with
  # write access explicitly enabled (kernels restrict /dev/cpu/*/msr writes
  # by default). Set both at module-load time rather than relying on
  # throttled's own runtime self-modprobe/self-enable, which races.
  boot.kernelModules = [ "msr" ];
  boot.extraModprobeConfig = ''
    options msr allow_writes=on
  '';

  environment.etc."throttled.conf".source = throttledConf;

  # Persistent, system-wide, NOT gated to eGPU presence -- this is a
  # firmware bug-fix (unmanaged sustained 64W package power), not a
  # gaming-only tradeoff. It would misbehave under any sustained heavy CPU
  # load (builds, video encode, ollama CPU fallback), not just games. See
  # README.md for the eGPU-gated performance toggle, which is separate and
  # lives in hardware/amd.nix.
  systemd.services.throttled = {
    description = "Enforce sane Intel CPU package power limits (fixes unmanaged PL1=64W BIOS default -- see README.md)";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.throttled}/bin/throttled.py --config /etc/throttled.conf";
      Restart = "on-failure";
      Environment = "PYTHONUNBUFFERED=1";
    };
  };

  environment.systemPackages = [ pkgs.throttled ];
}
