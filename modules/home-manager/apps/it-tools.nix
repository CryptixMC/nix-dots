{
  config,
  pkgs,
  lib,
  ...
}:

{

  home.packages = with pkgs; [
    # Network+ Study Tools
    wireshark # Network protocol analyzer
    nmap # Network scanner
    iputils # ip utilities like ping, arping, traceroute
    netcat # swiss-army knife for TCP/IP
    mtr # network diagnostic tool (traceroute and ping combined)
    bind # DNS utilities (dig, nslookup)
    tcpdump # command-line packet analyzer
    # GNS3 - Also typically requires manual installation and integration with virtualization

    # Other general IT/System Tools
    htop # interactive process viewer
    iotop # I/O monitor
    iftop # network interface monitor
    strace # system call tracer
    lsof # list open files
    usbutils # USB utilities (lsusb)
    pciutils # PCI utilities (lspci)
    file # determine file type
    jq # JSON processor
    yq # YAML processor
    bat # cat clone with syntax highlighting and Git integration
    delta # diff viewer
    ripgrep # grep alternative
    fd # find alternative
  ];

  # Optional: Configure some tools if needed
  # programs.wireshark.enable = true; # Enable Wireshark integration (This option does not exist for wireshark in home-manager)

  # You might want to add aliases for some commands in your shell configuration
  # For example, in your shell.nix:
  # programs.bash.shellAliases = {
  #   ll = "ls -l";
  #   la = "ls -la";
  # };
}
