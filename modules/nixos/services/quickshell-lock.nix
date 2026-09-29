{ ... }:
{
  # PAM stack for the Quickshell lock screen (LockService.qml). The default stack
  # plus fprintd's default gives fingerprint-or-password. Inert until the lock
  # is wired to a trigger; see TODO.md §5.
  security.pam.services.quickshell-lock = { };
}
