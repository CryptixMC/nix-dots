{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cpu; # eGPU isn't reliably present at boot; keep it CPU-only
  };
}
