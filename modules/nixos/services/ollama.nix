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
  };
}
