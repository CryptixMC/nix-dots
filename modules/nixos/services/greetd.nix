{ pkgs, lib, ... }:
let
  # --replace-fail so a changed placeholder fails the build instead of silently no-op'ing.
  greeterQml = pkgs.runCommand "quickshell-greeter-qml" { } ''
    cp -r ${lib.cleanSource ../../../desktop/greeter} $out
    chmod -R u+w $out
    # The repo's copy is a symlink into desktop/themes/, which isn't part of this source.
    cp --remove-destination ${../../../desktop/themes/ultraviolet/wallpapers/alyssa.png} $out/theme/wallpapers/alyssa.png
    substituteInPlace $out/modules/auth/SessionCommand.qml \
      --replace-fail 'exec Hyprland' 'exec ${lib.getExe pkgs.hyprland}'
  '';
in
{
  # Rollback: re-enable this line and remove the greetd/polkit config below. See TODO.md §4.
  # programs.regreet.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.dbus}/bin/dbus-run-session ${pkgs.cage}/bin/cage -s -d -- ${pkgs.quickshell}/bin/quickshell -p ${greeterQml}";
    # Password-only at the greeter by design (see fprintd.nix).
  };

  # Colon-free alias for the iGPU, used by AQ_DRM_DEVICES in SessionCommand.qml (that var is
  # colon-separated, so the by-path name pci-0000:00:02.0-card splits and Hyprland finds no GPU).
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card*", KERNELS=="0000:00:02.0", DRIVERS=="i915", SYMLINK+="dri/igpu"
  '';

  # Wallpaper handoff from the desktop session to the greeter, so $HOME can stay
  # 0700. setgid so files cryptix writes are readable by the greeter group.
  systemd.tmpfiles.rules = [
    "d /var/lib/quickshell-greeter 2750 cryptix greeter - -"
  ];

  # Pre-login Wi-Fi: saving a system-wide NM profile needs polkit auth. Scoped to the
  # greeter group, like GDM's rule, so an unattended console can't create profiles.
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
