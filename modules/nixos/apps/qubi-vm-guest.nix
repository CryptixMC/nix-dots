{
  config,
  pkgs,
  lib,
  nixpkgsPath,
  qubiPkg,
  qubiAppPkg,
  qubiAgentPkg,
  agentSshKey,
  qubiVm,
  ...
}:
# The Qubi development VM guest. This file is the single source of truth for
# what runs inside the machine; the host side lives in qubi-vm.nix.
let
  # The agent talks to the host's model server through the guest's bridge on
  # 8095, the same port the engine itself uses.
  manifestFile = pkgs.writeText "qubi-vm-manifest.toml" ''
    [[agent]]
    name = "qwen-local"
    consent = "ask"

    [agent.transport.acp_stdio]
    command = "${qubiAgentPkg}/bin/qwen"
    args = [ "--acp" ]

    [agent.transport.acp_stdio.env]
    OPENAI_API_KEY = "sk-local-noauth"
    OPENAI_BASE_URL = "http://127.0.0.1:8095/v1"
    OPENAI_MODEL = "Qwen3.5-9B-Q4_K_M"

    # The guest's own screen: the computer MCP server captures the :99 X
    # session and drives its mouse and keyboard, so a chat that runs in the
    # guest works the guest's app. The host reaches the same session over
    # VNC, so a human watches what the chat does.
    [[mcp]]
    name = "computer"
    command = "${qubiPkg}/bin/qubi-computer-mcp"
    args = [ ]
    start = "lazy"

    [mcp.env]
    ${if hyprlandMode then "WAYLAND_DISPLAY=wayland-1" else "DISPLAY=\":99\""}

    [mcp.tool_allow]
    fast = [ "*" ]
    light = [ "*" ]
    heavy = [ "*" ]
  '';

  # The desktop to run inside the guest: "x11" (Xvfb + openbox + x11vnc) or
  # "hyprland" (headless Hyprland + wayvnc).
  hyprlandMode = qubiVm.desktop == "hyprland";

  hyprConf = pkgs.writeText "hyprland.conf" ''
    monitor = HEADLESS-1, 1920x1080@60, 0x0, 1
    exec-once = hyprctl output create headless HEADLESS-1
    misc {
      disable_hyprland_logo = true
    }
  '';
in
{
  nixpkgs.config.allowUnfree = true;
  imports = [ "${nixpkgsPath}/nixos/modules/virtualisation/qemu-vm.nix" ];

  boot.loader.grub.enable = true;
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty0"
  ];
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "virtio_balloon"
    "virtio_console"
    "virtio_gpu"
  ];
  boot.kernelModules = [
    "kvm"
    "kvm_intel"
    "virtio_pci"
    "virtio_blk"
    "virtio_net"
    "virtio_balloon"
    "virtio_console"
    "virtio_gpu"
    # Host<->guest vsock transport and uinput for pointer injection.
    "virtio_vsock"
    "uinput"
  ];

  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  system.stateVersion = "26.11";

  systemd.services."serial-getty@ttyS0".wantedBy = [ "multi-user.target" ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    PubkeyAuthentication = true;
  };

  users.users.agent = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "kvm"
      "libvirt"
      "video"
      "render"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ agentSshKey ];
  };

  users.users.qubi = {
    isNormalUser = true;
    ignoreShellProgramCheck = true;
    group = "users";
    extraGroups = [
      "wheel"
      "kvm"
      "libvirt"
      "video"
      "render"
    ];
    shell = pkgs.zsh;
  };

  security.sudo.wheelNeedsPassword = false;

  services.qemuGuest.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  programs.zsh.enable = true;

  environment.systemPackages =
    with pkgs;
    [
      # The local ACP coding agent the engine's manifest points at. It speaks
      # ACP over stdio and runs on the host's model server through the bridge.
      qubiAgentPkg
      # Screen capture and pointer control for the guest's own X session.
      xorg-server
      xdotool
      scrot
      imagemagick
      wmctrl
      xclip
      openbox
      x11vnc
      # Wayland helpers, for a seatd-based session later on.
      grim
      slurp
      ydotool
      wtype
      wl-clipboard
      playwright
      htop
      btop
      jq
      socat
      spice-gtk
      virt-viewer
      git
      vim
      neovim
      zsh
      tmux
      wlrctl
    ]
    ++ lib.optionals hyprlandMode [
      hyprland
      wayvnc
    ];

  # The engine and the app talk over a unix socket in the qubi user's own
  # runtime directory. A dedicated directory avoids depending on a login
  # session existing for that uid.
  systemd.services.qubi-vm-prepare = {
    description = "Prepare Qubi VM environment";
    wantedBy = [ "multi-user.target" ];
    before = [ "qubi-engine.service" ];
    serviceConfig = {
      Type = "oneshot";
      # No shell: the unit names coreutils binaries directly so it cannot
      # break when a shell package is not in the image closure.
      ExecStart = [
        "${pkgs.coreutils}/bin/mkdir -p /home/qubi/.config/qubi/modules.d /home/qubi/.local/state"
        "${pkgs.coreutils}/bin/chown -R qubi /home/qubi"
      ];
      RemainAfterExit = true;
    };
  };

  # The engine's manifest declares the local ACP agent. It is seeded once, so
  # a manifest the user edits in the guest is never overwritten.
  systemd.services.qubi-vm-manifest = {
    description = "Seed the Qubi engine manifest with the local ACP agent";
    wantedBy = [ "multi-user.target" ];
    after = [ "qubi-vm-prepare.service" ];
    before = [ "qubi-engine.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${pkgs.coreutils}/bin/test ! -e /home/qubi/.config/qubi/manifest.toml";
      ExecStart = [
        "${pkgs.coreutils}/bin/mkdir -p /home/qubi/.config/qubi"
        "${pkgs.coreutils}/bin/cp ${manifestFile} /home/qubi/.config/qubi/manifest.toml"
        "${pkgs.coreutils}/bin/chown -R qubi /home/qubi/.config/qubi"
      ];
    };
  };

  systemd.services.qubi-engine = {
    description = "Qubi Engine";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "qubi-vm-prepare.service"
    ];
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      RuntimeDirectory = "qubi";
      # The host drives this engine over an ssh-forwarded socket, so the
      # socket has to be connectable by other users in the machine.
      RuntimeDirectoryMode = "0755";
      UMask = "0000";
      # The engine's own fallback server defaults to 127.0.0.1:8090, which
      # is the host's small-model port. The guest reaches the host's model
      # server through the bridge below, which listens on 8095.
      ExecStart = "${qubiPkg}/bin/qubi-engine --socket /run/qubi/qubi-engine.sock --llm-endpoint http://127.0.0.1:8095/v1/chat/completions";
      Restart = "on-failure";
      RestartSec = 5;
      Environment =
        lib.optionals (!hyprlandMode) [ "DISPLAY=:99" ]
        ++ lib.optionals hyprlandMode [ "WAYLAND_DISPLAY=wayland-1" ]
        ++ [
          "HOME=/home/qubi"
          "XDG_RUNTIME_DIR=/run/qubi"
          "XDG_CONFIG_HOME=/home/qubi/.config"
          "XDG_STATE_HOME=/home/qubi/.local/state"
          "XDG_DATA_HOME=/home/qubi/.local/share"
          "XDG_CACHE_HOME=/home/qubi/.cache"
          "QUBI_MODULES_DIR=/home/qubi/.config/qubi/modules.d"
          # The computer MCP server's child needs the display and the
          # screen tools on its PATH.
          "QUBI_MCP_RUNTIME_PATH=${pkgs.xdotool}/bin:${pkgs.scrot}/bin"
        ];
    };
  };

  # The app needs a display. A headless X server on :99 is the one display
  # that works in a VM with no GPU: grim needs Wayland, xdotool needs XTEST.
  systemd.services.qubi-xvfb = lib.mkIf (!hyprlandMode) {
    description = "Headless X server for the Qubi app session";
    wantedBy = [ "multi-user.target" ];
    after = [ "qubi-vm-prepare.service" ];
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      ExecStart = "${pkgs.xorg-server}/bin/Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp -ac -noreset";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [ "HOME=/home/qubi" ];
    };
  };

  systemd.services.qubi-wm = lib.mkIf (!hyprlandMode) {
    description = "Window manager for the Qubi app session";
    wantedBy = [ "multi-user.target" ];
    after = [ "qubi-xvfb.service" ];
    requires = [ "qubi-xvfb.service" ];
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      ExecStart = "${pkgs.openbox}/bin/openbox --config-file /etc/xdg/openbox/rc.xml";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "HOME=/home/qubi"
        "DISPLAY=:99"
      ];
    };
  };

  systemd.services.qubi-app = {
    description = "Qubi App (Tauri)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "qubi-engine.service"
    ]
    ++ (lib.optionals (!hyprlandMode) [ "qubi-xvfb.service" ])
    ++ (lib.optionals hyprlandMode [ "qubi-hyprland.service" ]);
    requires =
      (lib.optionals (!hyprlandMode) [ "qubi-xvfb.service" ])
      ++ (lib.optionals hyprlandMode [ "qubi-hyprland.service" ]);
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      ExecStart = "${qubiAppPkg}/bin/qubi-app";
      Restart = "on-failure";
      RestartSec = 5;
      Environment =
        (lib.optionals (!hyprlandMode) [
          "DISPLAY=:99"
          "GDK_BACKEND=x11"
        ])
        ++ (lib.optionals hyprlandMode [ "WAYLAND_DISPLAY=wayland-1" ])
        ++ [
          "HOME=/home/qubi"
          "QUBI_SOCKET=/run/qubi/qubi-engine.sock"
          "XDG_RUNTIME_DIR=/run/qubi"
          "XDG_CONFIG_HOME=/home/qubi/.config"
          "XDG_STATE_HOME=/home/qubi/.local/state"
          "LIBGL_ALWAYS_SOFTWARE=1"
          "WEBKIT_DISABLE_COMPOSITING_MODE=1"
          "WEBKIT_DISABLE_DMABUF_RENDERER=1"
        ];
    };
  };

  # Exports the guest's :99 session so a human can watch the app the same
  # way the automation screenshots it.
  systemd.services.qubi-vnc = {
    description = "VNC export of the Qubi app session";
    wantedBy = [ "multi-user.target" ];
    after =
      (lib.optionals (!hyprlandMode) [ "qubi-xvfb.service" ])
      ++ (lib.optionals hyprlandMode [ "qubi-hyprland.service" ]);
    requires =
      (lib.optionals (!hyprlandMode) [ "qubi-xvfb.service" ])
      ++ (lib.optionals hyprlandMode [ "qubi-hyprland.service" ]);
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      ExecStart = (
        if hyprlandMode then
          "${pkgs.wayvnc}/bin/wayvnc -r -S /run/qubi/wayvnc-raw.sock 0.0.0.0 ${toString qubiVm.vncPort}"
        else
          "${pkgs.x11vnc}/bin/x11vnc -display :99 -rfbport ${toString qubiVm.vncPort} -forever -shared -nopw -noxdamage"
      );
      Restart = "on-failure";
      RestartSec = 2;
      Environment = (
        if hyprlandMode then
          [
            "WAYLAND_DISPLAY=wayland-1"
            "XDG_RUNTIME_DIR=/run/qubi"
            "HOME=/home/qubi"
          ]
        else
          [ "HOME=/home/qubi" ]
      );
    };
  };

  # Headless Hyprland desktop (alternative to X11 session).
  systemd.services.qubi-hyprland = lib.mkIf hyprlandMode {
    description = "Headless Hyprland desktop";
    wantedBy = [ "multi-user.target" ];
    after = [
      "qubi-engine.service"
      "qubi-vm-prepare.service"
    ];
    requires = [ "qubi-engine.service" ];
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      Environment = [
        "HOME=/home/qubi"
        "XDG_RUNTIME_DIR=/run/qubi"
        "AQ_BACKENDS=headless"
        "WLR_BACKENDS=headless"
        "LIBGL_ALWAYS_SOFTWARE=1"
        "WAYLAND_DISPLAY=wayland-1"
      ];
      ExecStart = "${pkgs.hyprland}/bin/Hyprland --config ${hyprConf}";
      Restart = "on-failure";
      RestartSec = 2;
    };
    unitConfig = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
  };

  systemd.services.qubi-vnc-ws = lib.mkIf hyprlandMode {
    description = "WebSocket VNC export of the Qubi app session (Hyprland)";
    wantedBy = [ "multi-user.target" ];
    after = [ "qubi-hyprland.service" ];
    requires = [ "qubi-hyprland.service" ];
    serviceConfig = {
      Type = "simple";
      User = "qubi";
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc -r -w -S /run/qubi/wayvnc-ws.sock 0.0.0.0 ${toString (qubiVm.vncPort + 1)}";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/qubi"
        "HOME=/home/qubi"
      ];
    };
  };

  # The engine talks to a model server on its own loopback port. In the guest
  # that port has to lead to the host's server, which slirp reaches at
  # 10.0.2.2.
  systemd.services.qubi-model-bridge = {
    description = "Forward the guest's model port to the host's model server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8095,reuseaddr,fork TCP:10.0.2.2:8095";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.qubi-vsock = {
    description = "Qubi VSOCK listener for agent communication";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:5000,fork,reuseaddr EXEC:/run/current-system/sw/bin/bash,pty,stderr,setsid,sigint,sane";
      Restart = "on-failure";
      RestartSec = 5;
      User = "qubi";
      StandardInput = "null";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  services.logind = {
    enable = true;
    settings = {
    };
  };

  # VM settings for the bootable image (used by flake package `qubi-vm`).

  virtualisation = {
    useBootLoader = true;
    diskImage = "../disk.qcow2";
    graphics = false; # headless; SPICE handled by host
    memorySize = qubiVm.memorySize;
    cores = qubiVm.cores;
    forwardPorts = [
      {
        from = "host";
        host.port = qubiVm.sshPort;
        guest.port = 22;
      }
      {
        from = "host";
        host.port = qubiVm.vncPort;
        guest.port = qubiVm.vncPort;
      }
    ]
    ++ lib.optional hyprlandMode {
      from = "host";
      host.port = qubiVm.vncPort + 1;
      guest.port = qubiVm.vncPort + 1;
    };
    qemu.options = [
      "-spice port=${toString qubiVm.spicePort},disable-ticketing=on"
      # A VGA device so SPICE shows the guest console instead of a blank
      # framebuffer; -nographic keeps the serial console on stdio.
      "-vga std"
      # The kernel vhost-vsock transport: the host talks to the guest over
      # AF_VSOCK instead of ssh. No chardev is needed, the device opens
      # /dev/vhost-vsock itself.
      "-device vhost-vsock-pci,guest-cid=3"
    ];
  };

  # Root filesystem for boot loader
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  networking.firewall.allowedTCPPorts = [
    qubiVm.sshPort
    qubiVm.spicePort
    qubiVm.vncPort
  ]
  ++ lib.optional hyprlandMode (qubiVm.vncPort + 1);
  networking.firewall.allowedUDPPorts = [ ];
  # WebSocket VNC port is only open when running headless Hyprland.
  networking.firewall.extraCommands = lib.optionalString hyprlandMode "iptables -I INPUT -p tcp --dport ${toString (qubiVm.vncPort + 1)} -j ACCEPT";
}
