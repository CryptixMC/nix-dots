{ ... }:
{
  programs.ghostty = {
    enable = true;
    settings = {
      # Baseline before Quickshell ever writes a live theme — stylix's own
      # ghostty target (modules/style/stylix.nix, targets.qt is the only
      # target it disables) already generates a "stylix" theme file from
      # the same stylix.base16Scheme themes/ultraviolet/base16.yaml points
      # at, so this tracks the real palette automatically instead of
      # duplicating it by hand (the old hand-authored "ultraviolet" theme
      # here had drifted to a stale, pre-migration set of hex values).
      theme = "stylix";

      # Live theme sync: quickshell/theme/Theme.qml writes this file on
      # every theme change (background/foreground/cursor/selection/palette,
      # base16-to-ANSI-16 mapping) whenever the active Quickshell theme
      # changes. Per Ghostty's own config-file load-order semantics, an
      # included file's directives apply *after* the rest of the file that
      # included it, so this always wins over `theme = stylix` above
      # regardless of where this line falls in the generated config. The
      # `?` prefix means "don't error if missing" — true before Quickshell
      # has ever run once.
      config-file = "?~/.local/state/quickshell-ghostty-theme.conf";
    };
  };
}
