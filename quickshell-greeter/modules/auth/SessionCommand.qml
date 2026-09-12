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
QtObject {
    readonly property var argv: ["Hyprland"]
    readonly property var environment: ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland", "XDG_SESSION_DESKTOP=Hyprland"]
}
