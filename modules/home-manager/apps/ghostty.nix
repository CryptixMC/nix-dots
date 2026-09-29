{ ... }:
{
  programs.ghostty = {
    enable = true;
    settings = {
      # Baseline until Quickshell writes a live theme; stylix generates this from base16.yaml.
      theme = "stylix";

      # Written by desktop/shell/theme/Theme.qml on theme change. Included files
      # apply after the main config, so this overrides `theme`; `?` allows it to be missing.
      config-file = "?~/.local/state/quickshell-ghostty-theme.conf";
    };
  };
}
