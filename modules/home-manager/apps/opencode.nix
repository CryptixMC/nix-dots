{ pkgs, ... }:
{
  home.packages = [ pkgs.opencode ];

  # Fully declarative, unlike goose.nix's config.yaml: opencode has no
  # dock/undock runtime-mutation requirement in this pass (that's deferred,
  # see TODO.md §7), so there's no need for goose.nix's activation-script +
  # live-yq-edit approach here — a plain home.file is sufficient and safer
  # (no risk of clobbering a hand-edited config).
  #
  # opencode has no built-in Ollama preset, so it's wired up as a generic
  # OpenAI-compatible provider pointed at Ollama's own OpenAI-compatible
  # endpoint (confirmed real: `@ai-sdk/openai-compatible` + baseURL, per
  # opencode's own docs at opencode.ai/docs/providers). No cloud provider
  # blocks here — OpenRouter/Anthropic credentials are a separate,
  # human-only item (`goose configure` needs a real TTY, same story would
  # apply here).
  home.file.".config/opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    provider = {
      ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (local)";
        options = {
          baseURL = "http://localhost:11434/v1";
        };
        models = {
          "qwen2.5-coder:7b" = {
            tool_call = true;
          };
          "qwen2.5-coder:14b" = {
            tool_call = true;
          };
          "qwen3-coder:latest" = {
            tool_call = true;
          };
          "devstral:latest" = {
            tool_call = true;
          };
          "qwen3.6:latest" = {
            tool_call = true;
          };
        };
      };
    };
    # Mirrors ai-workstation.nix's current undocked default; superseded by
    # whichever (driver, model) combo wins the TODO.md §7 test matrix.
    model = "ollama/qwen2.5-coder:7b";
  };
}
