pragma Singleton
import QtQuick

// Fixed, not a runtime `wayland-sessions/*.desktop` glob — v1 is
// single-session (Hyprland only). Quickshell.DesktopEntries doesn't cover
// wayland-sessions/ anyway (confirmed against its qmltypes: it only reads
// XDG applications/ entries), so a real session picker would need
// hand-rolled Quickshell.Io.Process globbing — deferred, see the greeter
// plan's scope boundary.
//
// argv's value below is a build-time substitution target:
// modules/nixos/services/greetd.nix's `greeterQml` derivation runs
// substituteInPlace to swap in the real absolute Hyprland store path
// (lib.getExe pkgs.hyprland) before copying this tree into the Nix store.
// Deliberately NOT quoting that exact bracketed array literal anywhere
// else in this comment block — substituteInPlace matches the whole file,
// not just the one line, and an earlier version of this comment
// self-mangled into showing the already-substituted path instead of the
// original placeholder, found by inspecting the built store copy. Bare
// "Hyprland" relies on $PATH, which greetd's minimal session environment
// doesn't set up the way an interactive shell does — this file alone (e.g.
// run standalone in Phase 0) is never what actually reaches greetd.
// argv is a login-shell wrapper, not a bare exec: zsh reads ~/.zshenv (sourced
// by every zsh invocation, login or not) which in turn sources
// hm-session-vars.sh, so every home.sessionVariables entry reaches the
// compositor's own process environment -- something greetd's minimal exec
// path never delivered. The `-c` string itself execs the placeholder below,
// so the real binary replaces the shell PID: greetd/PAM still track a single
// process, exactly as they did with the old bare-exec argv.
// The `-c` element carries its own single quotes: greetd space-joins argv
// (no shell quoting) into `sh -c "... exec <argv>"`, so unquoted it would
// re-split into `zsh -l -c exec <path>` -- zsh runs a bare `exec`, exits 0,
// and the session ends instantly with nothing logged.
//
// AQ_DRM_DEVICES pins Aquamarine (Hyprland's renderer) to /dev/dri/igpu, a udev
// symlink (greetd.nix) for PCI 0000:00:02.0 -- the built-in GPU. It must be
// colon-free: the var is colon-separated, so a by-path name gets split. This way
// an eGPU dock/undock event can never change which card Hyprland starts on.
QtObject {
    readonly property var argv: ["zsh", "-l", "-c", "'exec Hyprland'"]
    readonly property var environment: ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland", "AQ_DRM_DEVICES=/dev/dri/igpu"]
}
