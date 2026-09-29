pragma Singleton
import QtQuick

// Single fixed session (Hyprland); a session picker is out of scope.
// greetd.nix substitutes the absolute Hyprland path into argv at build time;
// never quote argv's literal in a comment, substituteInPlace would rewrite it too.
// zsh -l sources hm-session-vars.sh so home.sessionVariables reach the compositor;
// exec keeps a single PID for greetd/PAM. The inner quotes are required: greetd
// space-joins argv into `sh -c`, and unquoted zsh would run a bare `exec` and exit.
// AQ_DRM_DEVICES pins Hyprland to the iGPU so eGPU hotplug can't change its card;
// the path must be colon-free since the variable is colon-separated.
QtObject {
    readonly property var argv: ["zsh", "-l", "-c", "'exec Hyprland'"]
    readonly property var environment: ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland", "AQ_DRM_DEVICES=/dev/dri/igpu"]
}
