{ ... }:
{
  # Bare declaration is enough — NixOS's PAM module gives a sensible default
  # stack (pam_unix auth/account/password/session) for any declared service,
  # same pattern already used for other single-purpose services in this
  # repo (see fprintd.nix's login/sudo entries). fprintd.nix's blanket
  # `services.fprintd.enable = true` also makes this default to
  # `fprintAuth = true` automatically, without needing to say so here — the
  # lock screen gets fingerprint-or-password for free, matching Omarchy's
  # reference implementation's dual-auth flow.
  #
  # Declaring this PAM service has zero effect on its own — nothing calls
  # into it until quickshell/modules/lock/LockService.qml actually drives a
  # PamContext with config: "quickshell-lock", which nothing currently
  # triggers automatically (see that file's own comments). Safe to ship
  # inert; see TODO.md §5 for what's left before wiring in a real trigger.
  security.pam.services.quickshell-lock = { };
}
