{ inputs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.twilight ];
  programs.zen-browser = {
    enable = true;
    # No `profiles` declared: the module asserts exactly one default profile, so
    # declaring any would displace the unmanaged live profile (see TODO.md).
  };
}
