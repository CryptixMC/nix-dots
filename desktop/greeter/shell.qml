import QtQuick
import Quickshell
import "modules/greeter"

// greetd greeter entry point (TODO.md §4), decoupled from the desktop shell.
// One Greeter per screen since the monitor layout is dock-dependent.
ShellRoot {
    Variants {
        model: Quickshell.screens

        Greeter {
            modelData: modelData
        }
    }
}
