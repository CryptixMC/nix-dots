{ pkgs, lib, ... }:
let
  # Injects the real absolute Hyprland path into SessionCommand.qml before
  # copying the tree into the store — see that file's own comment for the
  # exact substitution contract. Fails loudly (--replace-fail) if the
  # placeholder string ever changes shape, rather than silently no-op'ing.
  greeterQml = pkgs.runCommand "quickshell-greeter-qml" { } ''
    cp -r ${lib.cleanSource ../../../quickshell-greeter} $out
    chmod -R u+w $out
    substituteInPlace $out/modules/auth/SessionCommand.qml \
      --replace-fail '["Hyprland"]' '["${lib.getExe pkgs.hyprland}"]'
  '';
in
{
  # Hidden, not removed — was: `programs.regreet.enable = true;`. Flip back
  # to that (and remove the services.greetd/polkit config below) to roll
  # back instantly if the Quickshell greeter ever needs to be abandoned.
  # See TODO.md §2 and the greeter plan.
  # programs.regreet.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session.command =
      "${pkgs.dbus}/bin/dbus-run-session ${pkgs.cage}/bin/cage -s -d -- ${pkgs.quickshell}/bin/quickshell -p ${greeterQml}";
    # default_session.user left at the module's own default ("greeter") —
    # no dedicated system user needed, this greeter doesn't copy any
    # per-user config into a cache dir the way e.g. dms-greeter does.
    #
    # general.service left unset (defaults to "greetd") — this is the same
    # PAM service NixOS's greetd module already auto-generates (the `login`
    # stack), now governing this greeter exactly like it governed ReGreet.
    # fprintd.nix's `security.pam.services.greetd.fprintAuth = false;`
    # continues to mean exactly what it already means — no changes needed
    # there. Password-only at the greeter is the deliberate v1 scope
    # decision (see the greeter plan's Context section for why genuine
    # concurrent fingerprint+password isn't actually achievable here).
  };

  # GDM-style pre-login Wi-Fi: NetworkManager's own stock polkit policy
  # already lets any local active session scan/toggle-wifi/activate a
  # connection (org.freedesktop.NetworkManager's own .policy defaults) — no
  # rule needed for that. The one gap is persisting a *system-wide*
  # connection profile (settings.modify.system), which normally needs
  # interactive admin polkit auth — impossible pre-login. GDM ships an
  # equivalent rule scoped to its own `gdm` group
  # (gdm's data/polkit-gdm.rules.in) — this mirrors that exactly, scoped to
  # NixOS's greetd module's own `greeter` group (users.groups.greeter,
  # already defined by that module), deliberately not broadened to "any
  # local active session" — that would let an unattended physical console
  # silently create persistent system-wide network profiles.
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
