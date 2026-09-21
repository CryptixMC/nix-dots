{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    # eGPU is hotplugged over Thunderbolt and may not be present at boot, so ollama can
    # start CPU-only; egpu-bar-fix.service (amd.nix) restarts it once the eGPU is bound.
    package = pkgs.ollama-rocm;

    # Ollama's runtime default silently caps context at ~4096 regardless of a model's trained
    # length. 16384 (not 32768) is the RAM-safe ceiling on this 38GB no-swap laptop -- 32768
    # risks OOM on the largest pulled model (qwen3.6:latest) when undocked.
    environmentVariables.OLLAMA_CONTEXT_LENGTH = "16384";

    # flash attention + q8_0 KV cache: verified safe on this gfx1030 eGPU via ROCm, roughly
    # halves KV cache memory.
    # keep-alive raised from Ollama's 5m default to 30m to avoid reloading between turns.
    # max_loaded_models=2 lets a primary + secondary (toolshim/subagent) model stay resident;
    # accepted OOM risk undocked if both are large, not an oversight.
    environmentVariables.OLLAMA_FLASH_ATTENTION = "1";
    environmentVariables.OLLAMA_KV_CACHE_TYPE = "q8_0";
    environmentVariables.OLLAMA_KEEP_ALIVE = "30m";
    environmentVariables.OLLAMA_MAX_LOADED_MODELS = "2";
  };
}
