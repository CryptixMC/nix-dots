{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    # The RX 6800 XT eGPU is hotplugged over Thunderbolt and isn't reliably
    # present when ollama.service starts at boot, so it may come up CPU-only.
    # egpu-bar-fix.service (modules/nixos/hardware/amd.nix) restarts ollama
    # once the GPU's PCIe BAR is fixed up and the amdgpu driver is bound,
    # so it picks up ROCm shortly after the eGPU is plugged in.
    package = pkgs.ollama-rocm;

    # Ollama's own runtime default (unrelated to a model's trained context
    # length) silently caps every model at ~4096 tokens unless overridden —
    # confirmed live via `journalctl -u ollama.service` showing
    # `n_ctx_slot = 4096` for qwen2.5-coder:7b despite it reporting a
    # trained `context length: 32768` in `ollama show`. Truncated context
    # mid-agentic-task (tool schemas + history getting cut) is a plausible
    # root cause for the tool-calling flakiness logged in TODO.md §7. 16384
    # (not 32768) is chosen for RAM safety on this 38GB/no-swap laptop: at
    # 32768 the largest pulled model's (qwen3.6:latest, 23GB weights)
    # resident footprint including KV cache comes out to ~33.5GB, at/over
    # the ~33GB free when undocked (no eGPU) — a real OOM risk. 16384 keeps
    # every pulled model under ~28GB total while still quadrupling the
    # previous silent default.
    environmentVariables.OLLAMA_CONTEXT_LENGTH = "16384";

    # flash attention and q8_0 KV cache were verified safe on this gfx1030
    # AMD RX 6800 XT eGPU via ROCm through a real live test (clean startup,
    # flash_attn enabled, correct coherent inference output, zero errors) --
    # roughly halves KV cache memory at this context length.
    # keep-alive is set explicitly to 30 minutes since the previous undeclared
    # default was 5 minutes, too short for comfortably back-to-back
    # invocations without re-loading the model between turns.
    # max_loaded_models is set to 2 to allow a primary model and a second
    # model (such as a toolshim or subagent model) to stay resident together,
    # at some memory risk on this 38GB no-swap laptop if two large models
    # are both requested at once while undocked with no eGPU VRAM to offload
    # into -- this is an accepted tradeoff, not an oversight.
    environmentVariables.OLLAMA_FLASH_ATTENTION = "1";
    environmentVariables.OLLAMA_KV_CACHE_TYPE = "q8_0";
    environmentVariables.OLLAMA_KEEP_ALIVE = "30m";
    environmentVariables.OLLAMA_MAX_LOADED_MODELS = "2";
  };
}
