# Quickshell shell

Replacement for Waybar + Walker, built with [Quickshell](https://quickshell.org). Default bar and launcher as of [TODO.md](../TODO.md) §3's "Once at parity" milestone — Waybar and Walker are hidden (packages/config disabled, not deleted) rather than removed, so either can be restored by reversing the changes noted there.

Run standalone, without touching the rest of the system:

    quickshell -p ./quickshell

`SUPER+R` toggles the launcher — see [modules/home-manager/wm/hyprland.nix](../modules/home-manager/wm/hyprland.nix) for this and the rest of the bar/launcher-related binds.

Note: since this directory lives inside the nix-dots flake, new files need `git add`ing (even unstaged/uncommitted) before any Nix command will see them — flakes only evaluate git-tracked files.
