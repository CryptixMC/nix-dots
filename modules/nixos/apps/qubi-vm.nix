{
  pkgs,
  lib,
  config,
  qubiVmPkg ? null,
  qubiVm ? { },
  ...
}:
let
  cfg = config.services.qubi.vm;

  sshPort = qubiVm.sshPort or 2222;
  spicePort = qubiVm.spicePort or 5900;
  vncPort = qubiVm.vncPort or 5901;
  agentUser = qubiVm.agentUser or "agent";

  vmCli = import ../../../lib/qubi-vm-cli.nix {
    inherit pkgs;
    vmRunner = if qubiVmPkg == null then "" else "${qubiVmPkg}/bin/run-nixos-vm";
    inherit
      sshPort
      spicePort
      vncPort
      agentUser
      ;
  };
in
{
  options.services.qubi.vm = {
    enable = lib.mkEnableOption "Qubi development VM helpers on this host";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start the Qubi development VM at boot";
    };
  };

  # The guest system lives in modules/nixos/apps/qubi-vm-guest.nix and is
  # instantiated once in flake.nix; the machine itself is the flake package
  # `qubi-vm`. This module only wires the host side to it.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ vmCli ];

      environment.etc."qubi-vm-info".text = ''
        Qubi VM Connection Info:
        ========================
        SSH:   ssh -p ${toString sshPort} ${agentUser}@localhost
        SPICE: spicy -h localhost -p ${toString spicePort}
        VNC:   vncviewer localhost:${toString vncPort}
        Model: http://10.0.2.2:8095/v1 (the host's llama-server, as the guest sees it)
      '';
    })
    (lib.mkIf (cfg.enable && cfg.autoStart && qubiVmPkg != null) {
      systemd.tmpfiles.rules = [
        "d /var/lib/qubi-vm 0755 root root -"
      ];

      systemd.services.qubi-vm = {
        enable = true;
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${qubiVmPkg}/bin/run-nixos-vm";
          Restart = "on-failure";
          RestartSec = 10;
          Environment = "NIX_DISK_IMAGE=/var/lib/qubi-vm/disk.qcow2";
        };
      };
    })
  ];
}
