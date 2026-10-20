# Host-side helper for the Qubi development VM. Boots the machine, reaches
# the guest over SSH, drives the guest's X session (screenshots, mouse,
# keyboard) and forwards the guest engine socket back to the host.
{
  pkgs,
  vmRunner,
  sshPort ? 2222,
  spicePort ? 5900,
  vncPort ? 5901,
  agentUser ? "agent",
  display ? ":99",
}:
pkgs.writeShellScriptBin "qubi-vm" ''
  set -euo pipefail

  RUNNER=${pkgs.lib.escapeShellArg vmRunner}
  SSH_PORT=${toString sshPort}
  SPICE_PORT=${toString spicePort}
  VNC_PORT=${toString vncPort}
  AGENT=${pkgs.lib.escapeShellArg agentUser}
  DISPLAY_NUM=${pkgs.lib.escapeShellArg display}

  STATE="''${XDG_STATE_HOME:-$HOME/.local/state}/qubi-vm"
  DISK="''$STATE/disk.qcow2"
  PIDFILE="''$STATE/qemu.pid"
  LOGFILE="''$STATE/qemu.log"
  SHOT="/tmp/qubi-shot.png"
  KNOWN_HOSTS="''${HOME}/.ssh/qubi-vm-known-hosts"

  ssh_vm() {
    ssh -p "$SSH_PORT" \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$KNOWN_HOSTS" \
      -o ConnectTimeout=10 \
      "$AGENT@localhost" "$@"
  }

  # ssh does not forward environment variables, so the display has to be
  # part of the remote command line.
  guest_display() {
    local cmd="DISPLAY=$DISPLAY_NUM"
    local a
    for a in "$@"; do
      cmd="$cmd $(printf '%q' "$a")"
    done
    ssh_vm "$cmd"
  }

  # The overlay only stays valid while the image it was created from is the
  # same one, so a rebuilt image gets a fresh disk instead of a broken one.
  prepare_disk() {
    mkdir -p "$STATE"
    local backing
    backing=$(grep -oE '(^| )-b [^ ]+' "$RUNNER" | head -1 | awk '{print $NF}' || true)
    if [ -n "''${backing:-}" ] && [ -e "$DISK" ]; then
      if [ "$(cat "$STATE/backing" 2>/dev/null || true)" != "$backing" ]; then
        echo "qubi-vm: image changed, recreating the disk overlay"
        rm -f "$DISK"
        # A fresh disk means a fresh guest host key, so the recorded one
        # has to go with it or ssh refuses to connect.
        rm -f "$KNOWN_HOSTS"
      fi
    fi
    echo "''$backing" > "$STATE/backing"
  }

  cmd_boot() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "qubi-vm: already running (pid $(cat "$PIDFILE"))"
      return 0
    fi
    prepare_disk
    mkdir -p "$STATE"
    NIX_DISK_IMAGE="$DISK" nohup "$RUNNER" > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    echo "qubi-vm: booting (pid $(cat "$PIDFILE")), log $LOGFILE"
    for _ in $(seq 1 60); do
      if ssh_vm true >/dev/null 2>&1; then
        echo "qubi-vm: guest is up on ssh port $SSH_PORT"
        return 0
      fi
      sleep 2
    done
    echo "qubi-vm: guest did not answer on ssh port $SSH_PORT; see $LOGFILE" >&2
    return 1
  }

  cmd_stop() {
    if [ -f "$STATE/tunnel.pid" ]; then
      kill "$(cat "$STATE/tunnel.pid")" 2>/dev/null || true
      rm -f "$STATE/tunnel.pid"
    fi
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
    fi
  }

  cmd_status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "qubi-vm: running (pid $(cat "$PIDFILE"))"
    else
      echo "qubi-vm: not running"
    fi
    ssh_vm 'systemctl is-active qubi-engine qubi-xvfb qubi-app 2>&1 | tr "\n" " "; echo' || true
  }

  cmd_shot() {
    local out="''${1:-$STATE/shot.png}"
    ssh_vm "DISPLAY=$DISPLAY_NUM scrot -o $SHOT"
    ssh_vm "cat $SHOT" > "$out"
    echo "$out"
  }

  cmd_move() {
    guest_display xdotool mousemove "$1" "$2"
  }

  cmd_click() {
    guest_display xdotool mousemove "$1" "$2" click "''${3:-1}"
  }

  cmd_type() {
    guest_display xdotool type --delay 25 -- "$1"
  }

  cmd_key() {
    guest_display xdotool key -- "$1"
  }

  cmd_run() {
    ssh_vm "$@"
  }

  cmd_put() {
    ssh_vm "cat > '$2'" < "$1"
    echo "qubi-vm: put $1 -> $2"
  }

  cmd_get() {
    ssh_vm "cat '$2'" > "$1"
    echo "qubi-vm: get $2 -> $1"
  }

  # Forwards the guest's engine socket so a host-side Qubi can drive the
  # engine running inside the machine.
  cmd_tunnel() {
    local local_sock="''${1:-$STATE/guest-engine.sock}"
    mkdir -p "$(dirname "$local_sock")"
    rm -f "$local_sock"
    ssh -N \
      -p "$SSH_PORT" \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$KNOWN_HOSTS" \
      -o ExitOnForwardFailure=yes \
      -L "$local_sock":/run/qubi/qubi-engine.sock \
      "$AGENT@localhost" > "$STATE/tunnel.log" 2>&1 &
    echo $! > "$STATE/tunnel.pid"
    echo "qubi-vm: guest engine socket forwarded to $local_sock"
  }

  cmd_view() {
    cat <<EOF
  SSH:   ssh -p $SSH_PORT $AGENT@localhost
  SPICE: spicy -h localhost -p $SPICE_PORT
  VNC:   vncviewer localhost:$VNC_PORT
  Model: http://10.0.2.2:8095/v1 (the host's llama-server, reachable from the guest)
  EOF
  }

  case "''${1:-}" in
    boot) shift; cmd_boot "$@" ;;
    stop) shift; cmd_stop "$@" ;;
    status) shift; cmd_status "$@" ;;
    ssh) shift; exec ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" "$AGENT@localhost" "$@" ;;
    shot) shift; cmd_shot "$@" ;;
    move) shift; cmd_move "$@" ;;
    click) shift; cmd_click "$@" ;;
    type) shift; cmd_type "$@" ;;
    key) shift; cmd_key "$@" ;;
    run) shift; cmd_run "$@" ;;
    put) shift; cmd_put "$@" ;;
    get) shift; cmd_get "$@" ;;
    tunnel) shift; cmd_tunnel "$@" ;;
    view) shift; cmd_view "$@" ;;
    *)
      echo "usage: qubi-vm {boot|stop|status|ssh|run|put|get|shot|move|click|type|key|tunnel|view}" >&2
      exit 2
      ;;
  esac
''
