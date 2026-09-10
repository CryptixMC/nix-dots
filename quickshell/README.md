# Quickshell shell (WIP)

Experimental replacement for Waybar + Walker, built with [Quickshell](https://quickshell.org). Lives in-tree but isn't wired into the flake/home-manager yet — see [TODO.md](../TODO.md) §3 for the full plan.

Run standalone, without touching the rest of the system:

    quickshell -p ./quickshell

Toggle against the current Waybar/Walker setup once the `SUPER SHIFT, up/down` binds land in [modules/home-manager/wm/hyprland.nix](../modules/home-manager/wm/hyprland.nix).

Note: since this directory lives inside the nix-dots flake, new files need `git add`ing (even unstaged/uncommitted) before any Nix command will see them — flakes only evaluate git-tracked files.
