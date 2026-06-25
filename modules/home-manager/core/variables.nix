{ ... }:
{
  home.sessionVariables = {
    CLAUDE_CODE_EXECUTABLE = "/run/current-system/sw/bin/claude";
  };

  systemd.user.sessionVariables = {
    CLAUDE_CODE_EXECUTABLE = "/run/current-system/sw/bin/claude";
  };
}
