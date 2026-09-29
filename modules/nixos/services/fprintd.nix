{ ... }:
{
  services.fprintd.enable = true;

  # fprintAuth defaults on for every PAM service. Off for sshd, where every
  # password login would otherwise wait out the fprintd timeout.
  security.pam.services.sshd.fprintAuth = false;

  security.pam.services.login.fprintAuth = true; # TTY login
  security.pam.services.sudo.fprintAuth = true; # terminal sudo

  # pam_fprintd runs before the password prompt (30s default timeout); shorten
  # it so falling through to a password is quick.
  security.pam.services.sudo.rules.auth.fprintd.settings = {
    timeout = 5;
    "max-tries" = 2;
  };
  security.pam.services.login.rules.auth.fprintd.settings = {
    timeout = 5;
    "max-tries" = 2;
  };

  # Off for greetd: fprintd in greeters has known issues blocking password login
  # or bypassing auth. See TODO.md §2.
  security.pam.services.greetd.fprintAuth = false;
}
