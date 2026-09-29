{ pkgs, ... }:
{
  # MCP servers for coding agents working in this repo. They're on PATH so
  # any agent's config can name them by command; .mcp.json is the shared
  # project-level declaration. nixd comes from core/packages.nix.
  home.packages = with pkgs; [
    mcp-nixos
    context7-mcp
    mcp-language-server
  ];
}
