{ pkgs, lib, ... }:
let
  # Injects the real Hyprland path into SessionCommand.qml before copying into the store;
  # --replace-fail so a changed placeholder string fails loudly instead of silently no-op'ing.
  greeterQml = pkgs.runCommand "quickshell-greeter-qml" { } ''
    cp -r ${lib.cleanSource ../../../quickshell-greeter} $out
    chmod -R u+w $out
    substituteInPlace $out/modules/auth/SessionCommand.qml \
      --replace-fail '["Hyprland"]' '["${lib.getExe pkgs.hyprland}"]'
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
