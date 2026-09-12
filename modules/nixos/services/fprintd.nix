{ ... }:
{
  services.fprintd.enable = true;

  # NixOS's fprintAuth default is `services.fprintd.enable`, i.e. it applies
  # to *every* PAM service unless overridden per-service — there's no
  # blanket opt-out in this nixpkgs pin. Explicitly disable it anywhere that
  # would be actively bad:
  #  - sshd: no local sensor is reachable over SSH, so every password login
  #    would hang for the full fprintd timeout before falling through.
  #  - greetd: see the note below.
  security.pam.services.sshd.fprintAuth = false;

  security.pam.services.login.fprintAuth = true; # TTY login
  security.pam.services.sudo.fprintAuth = true; # terminal sudo

  # pam_fprintd.so is "sufficient" and runs before pam_unix (password), and
  # its default timeout is 30s — so a failed/hesitant scan blocks typing a
  # password until it times out. Shorten both so the fall-through to a
  # password prompt is fast (a few seconds) instead of a long wait. This
  # can't make fingerprint and password available *simultaneously* — PAM's
  # conversation model for a plain terminal is sequential, not racy — but it
  # makes the wait short enough not to matter.
  security.pam.services.sudo.rules.auth.fprintd.settings = {
    timeout = 5;
    "max-tries" = 2;
  };
  security.pam.services.login.rules.auth.fprintd.settings = {
    timeout = 5;
    "max-tries" = 2;
  };

  # Deliberately kept off for the "greetd" PAM service (would otherwise
  # default to on) — there are reported PAM/fprintd + greeter interactions
  # (tuigreet, GDM, KDE lockscreen) that can end up blocking password login
  # entirely or, in some configs, bypassing auth. Worth its own careful pass
  # once ReGreet's plain password flow is confirmed solid. See TODO.md §1/§2.
  security.pam.services.greetd.fprintAuth = false;
}
