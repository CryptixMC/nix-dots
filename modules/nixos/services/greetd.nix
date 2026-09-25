{ pkgs, lib, ... }:
let
  # Injects the real Hyprland path into SessionCommand.qml before copying into the store;
  # --replace-fail so a changed placeholder string fails loudly instead of silently no-op'ing.
  greeterQml = pkgs.runCommand "quickshell-greeter-qml" { } ''
    cp -r ${lib.cleanSource ../../../quickshell-greeter} $out
    chmod -R u+w $out
    substituteInPlace $out/modules/auth/SessionCommand.qml \
      --replace-fail 'exec Hyprland' 'exec ${lib.getExe pkgs.hyprland}'
  '';
in
{
  # Rollback: re-enable this line and remove services.greetd/polkit config below to revert
  # to ReGreet. See TODO.md §2.
  # programs.regreet.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session.command =
      "${pkgs.dbus}/bin/dbus-run-session ${pkgs.cage}/bin/cage -s -d -- ${pkgs.quickshell}/bin/quickshell -p ${greeterQml}";
    # default_session.user left at module default ("greeter") -- no per-user config to copy.
    # general.service left unset (defaults to "greetd" PAM stack) -- same as it governed ReGreet.
    # Password-only at the greeter is deliberate v1 scope (concurrent fingerprint+password isn't achievable here).
  };

  # Shared handoff directory for the greeter's live wallpaper: the desktop
  # session (cryptix, uid 1000) writes a resolved snapshot of whatever
  # wallpaper is actually on screen right now; the "greeter" system user
  # (uid 988, pre-login, no PAM session of its own yet) reads it. Neither
  # side gets access to the other's home directory -- $HOME stays 0700, as
  # it should -- this is the one door between them, and it only ever
  # carries one image file plus a two-key JSON sidecar. See Theme.qml's
  # syncGreeterWallpaper() for the write side and quickshell-greeter/
  # modules/greeter/Wallpaper.qml for the read side.
  #
  # setgid (the leading 2) makes every file cryptix creates inside inherit
  # the "greeter" group automatically, so the greeter session can read them
  # without a chown after every write.
  # Colon-free alias for the iGPU, used by AQ_DRM_DEVICES in SessionCommand.qml (that var is
  # colon-separated, so the by-path name pci-0000:00:02.0-card splits and Hyprland finds no GPU).
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card*", KERNELS=="0000:00:02.0", DRIVERS=="i915", SYMLINK+="dri/igpu"
  '';

  systemd.tmpfiles.rules = [
    "d /var/lib/quickshell-greeter 2750 cryptix greeter - -"
  ];

  # GDM-style pre-login Wi-Fi: NetworkManager's stock policy already allows scan/connect for
  # any active session; the gap is persisting a system-wide profile, which needs polkit auth
  # normally impossible pre-login. Mirrors GDM's own gdm-group rule, scoped to the greeter
  # group (not "any session") to avoid an unattended console creating persistent profiles.
  environment.etc."polkit-1/rules.d/49-carbon-greeter.rules".text = ''
    polkit.addRule(function(action, subject) {
        if (!subject.isInGroup("greeter"))
            return undefined;
        if (action.id == "org.freedesktop.NetworkManager.settings.modify.system" &&
            subject.local && subject.active) {
            return polkit.Result.YES;
        }
    });
  '';
}
