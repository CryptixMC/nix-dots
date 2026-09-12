import QtQuick
import Quickshell
import "modules/greeter"

// Entry point for the greetd greeter (see TODO.md §2 and the greeter plan).
// Deliberately separate from quickshell/shell.qml — this runs as the
// unprivileged "greeter" system user pre-login, with zero coupling to the
// daily-driver bar/launcher shell.
//
// Per-screen Variants, mirroring quickshell/shell.qml's Bar pattern —
// matters concretely here since this laptop's monitor layout is
// dock-dependent (1 screen undocked, 3 docked).
ShellRoot {
    Variants {
        model: Quickshell.screens

        Greeter {
            modelData: modelData
        }
    }
}
