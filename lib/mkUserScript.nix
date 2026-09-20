# Shell prelude for a root-context systemd oneshot that needs to reach into
# the logged-in user's session (a user-scoped systemd unit, hyprctl, etc.).
# Splice the result into a writeShellScript/scriptWithPath body; it defines
# $RUNTIME_DIR and an as_user() function.
#
# Doesn't cover discovering HYPRLAND_INSTANCE_SIGNATURE -- callers that need
# it (hyprctl specifically) layer that on top locally, e.g.:
#   HYPR_SIG=$(ls -t "$RUNTIME_DIR/hypr" 2>/dev/null | head -n1)
#   hyprctl_user() { as_user env HYPRLAND_INSTANCE_SIGNATURE="$HYPR_SIG" hyprctl "$@"; }
# (chained `env A=1 env B=2 cmd` is valid -- each env sets its var and execs
# the rest, which is itself another env invocation). Kept out of this prelude
# because finding the live Hyprland instance is a distinct concern from user-
# session mechanics, and not every caller needs it (see ai-workstation.nix's
# plain `as_user bash -lc "qubi-state-sync"`).
{ user }:
''
  RUNTIME_DIR="/run/user/$(id -u ${user})"
  as_user() {
    runuser -u ${user} -- env XDG_RUNTIME_DIR="$RUNTIME_DIR" "$@"
  }
''
