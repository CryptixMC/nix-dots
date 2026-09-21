# Quickshell shell

Replacement for Waybar + Walker, built with [Quickshell](https://quickshell.org). Quickshell's own bar ([modules/bar/](modules/bar/)) and launcher ([modules/launcher/](modules/launcher/)) fully replaced Waybar and Walker; both were deleted outright, with no hidden config or "re-enable if needed" fallback left in the repo.

Run standalone, without touching the rest of the system:

    quickshell -p ./quickshell

`SUPER+R` toggles the launcher — see [modules/home-manager/wm/hyprland.nix](../modules/home-manager/wm/hyprland.nix) for this and the rest of the bar/launcher-related binds.

Note: since this directory lives inside the nix-dots flake, new files need `git add`ing (even unstaged/uncommitted) before any Nix command will see them — flakes only evaluate git-tracked files.
