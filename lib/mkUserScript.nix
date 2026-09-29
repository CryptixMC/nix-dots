# Shell prelude for root-context scripts that act in the user's session.
# Defines $RUNTIME_DIR and as_user(). Callers needing hyprctl add their own
# HYPRLAND_INSTANCE_SIGNATURE lookup on top.
{ user }:
''
  RUNTIME_DIR="/run/user/$(id -u ${user})"
  as_user() {
    runuser -u ${user} -- env XDG_RUNTIME_DIR="$RUNTIME_DIR" "$@"
  }
''
