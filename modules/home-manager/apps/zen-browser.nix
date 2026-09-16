{ inputs, ... }:
{
  imports = [ inputs.zen-browser.homeModules.twilight ];
  programs.zen-browser = {
    enable = true;
    # any other options under `programs.firefox` are also supported here.
    # see `man home-configuration.nix`.

    # Tried adding a second, non-default `profiles.catppuccin` block here
    # to enable the real `catppuccin/zen-browser` preset (confirmed live
    # via `nix eval`: `programs.zen-browser.profiles.<name>.presets.
    # catppuccin.{enable,accent,flavor}` are real options) as a zero-risk
    # opt-in alongside the existing self-managed live profile
    # (`~/.config/zen/huedeu9v.Default Profile`). Reverted: the module
    # hard-asserts "exactly one default Zen profile" the moment *any*
    # profile is declared, and it has no concept of the pre-existing
    # external profile to count against that — so `isDefault = false`
    # alone fails to eval, and `isDefault = true` risks changing which
    # profile Zen actually launches into by default. There's no
    # zero-risk path here without first deciding how to bring the live
    # profile under home-manager's management, exactly as this repo's own
    # TODO.md already flagged — confirmed by a real eval failure this
    # session, not just a hunch.
  };
}
