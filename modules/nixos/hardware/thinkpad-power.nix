{ pkgs, ... }:
let
  # The BIOS/EC ships an unmanaged sustained PL1 of 64W (stock i7-1260P is
  # 28W), which heat-soaks the chassis. throttled rewrites PL1/PL2 on a timer
  # because the EC keeps resetting them. Values are conservative, not tuned
  # (see README.md for the tuning method).
  throttledConf = pkgs.writeText "throttled.conf" ''
    [GENERAL]
    Enabled: True
    Sysfs_Power_Path: /sys/class/power_supply/AC*/online
    Autoreload: True

    # PL1 sized for what the chassis can cool; PL2 stays short so bursts still turbo.
    [AC]
    Update_Rate_s: 5
    PL1_Tdp_W: 35
    PL1_Duration_s: 28
    PL2_Tdp_W: 54
    PL2_Duration_S: 0.002
    Trip_Temp_C: 90
    cTDP: 0
    Disable_BDPROCHOT: False

    # Close to throttled's stock defaults.
    [BATTERY]
    Update_Rate_s: 30
    PL1_Tdp_W: 20
    PL1_Duration_s: 28
    PL2_Tdp_W: 35
    PL2_Duration_S: 0.002
    Trip_Temp_C: 80
    cTDP: 0
    Disable_BDPROCHOT: False

    # No undervolt.
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
  # throttled needs writable MSRs; set up at boot since its own runtime modprobe races.
  boot.kernelModules = [ "msr" ];
  boot.extraModprobeConfig = ''
    options msr allow_writes=on
  '';

  environment.etc."throttled.conf".source = throttledConf;

  # Always on, not eGPU-gated: it fixes a firmware bug that affects any sustained
  # CPU load. The eGPU performance toggle is separate (hardware/amd.nix).
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
