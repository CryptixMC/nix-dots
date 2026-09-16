{ pkgs, lib, ... }:

let
  # Rewrites ~/.config/goose/config.yaml's active provider/model in place
  # from /run/ai-workstation/state.json (written by ai-workstation-{dock,
  # undock}-sync.service in modules/nixos/apps/ai-workstation.nix, or by
  # ai-workstation-gaming-start below). Deliberately does nothing if either
  # file is missing rather than guessing a schema — config.yaml only
  # exists once `goose configure` has been run interactively at least
  # once, and its exact on-disk key names weren't fully confirmed against
  # a live install at authoring time (see the plan doc's Phase 1b section).
  # Verify at implementation time: does Goose Desktop pick this up on next
  # launch/new-session, or does it maintain a separate settings store from
  # the CLI?
  gooseStateSync = pkgs.writeShellScriptBin "goose-state-sync" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.yq-go
        pkgs.hyprland
      ]
    }:$PATH

    STATE_FILE=/run/ai-workstation/state.json
    CONFIG_FILE="$HOME/.config/goose/config.yaml"

    # HYPRLAND_INSTANCE_SIGNATURE isn't in this script's env when invoked
    # via `runuser ... bash -lc` from a root-context systemd oneshot — a
    # login shell doesn't inherit the desktop session's env. Discover it
    # the same way amd.nix's hyprctl_user() does, so notify below actually
    # reaches the running compositor instead of silently no-op'ing.
    export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -n1)

    if [ ! -f "$STATE_FILE" ]; then
      echo "[goose-state-sync] no state file at $STATE_FILE yet — nothing to sync" >&2
      exit 0
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "[goose-state-sync] $CONFIG_FILE doesn't exist yet — run 'goose configure' first" >&2
      exit 0
    fi

    # -r unwraps the scalar to its raw form — without it, yq preserves the
    # double-quoted "style" tag from the JSON source and prints literal
    # quote characters as part of the string (e.g. '"docked"' instead of
    # docked), which then breaks both the string comparisons below and the
    # later yq -i writes (embeds stray quotes into the target expression).
    state=$(yq -r '.state' "$STATE_FILE")
    provider=$(yq -r '.provider' "$STATE_FILE")
    model=$(yq -r '.model' "$STATE_FILE")

    if [ "$state" = "gaming" ] || [ "$provider" = "null" ]; then
      yq -i '.GOOSE_PROVIDER = "openrouter"' "$CONFIG_FILE"
      hyprctl notify -1 4000 "rgb(89dceb)" "Gaming: local model evicted, Goose routed to OpenRouter" 2>/dev/null || true
    else
      yq -i ".GOOSE_PROVIDER = \"$provider\"" "$CONFIG_FILE"
      yq -i ".GOOSE_MODEL = \"$model\"" "$CONFIG_FILE"
      # GOOSE_PROVIDER/GOOSE_MODEL alone aren't enough: a `goose acp` session
      # (the chat overlay's backend, see quickshell/modules/chat/
      # GooseAcpSession.qml) actually reads the model from
      # `providers.<provider>.model`, confirmed live — this script wrote
      # only the top-level keys for months without that ever being
      # noticed, since `goose run`/CLI sessions apparently don't hit the
      # same mismatch. Keep both in sync.
      if [ "$(yq -r ".providers.$provider" "$CONFIG_FILE")" != "null" ]; then
        yq -i ".providers.$provider.model = \"$model\"" "$CONFIG_FILE"
      fi
      hyprctl notify -1 4000 "rgb(89dceb)" "AI tier: $state ($model) — new Goose sessions will use it" 2>/dev/null || true
    fi
  '';

  # SUPER+G's gaming keybind (modules/home-manager/wm/hyprland.nix) wraps
  # gamescope launch with these two. Evicts the loaded model instantly via
  # `ollama stop` (no service restart needed, GPU stays physically bound)
  # and forces Goose's config to openrouter so a new session mid-game
  # doesn't try to hit a model that just got evicted from VRAM.
  aiWorkstationGamingStart = pkgs.writeShellScriptBin "ai-workstation-gaming-start" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.yq-go
        pkgs.ollama
      ]
    }:$PATH

    STATE_FILE=/run/ai-workstation/state.json

    if [ -f "$STATE_FILE" ]; then
      current_model=$(yq -r '.model' "$STATE_FILE" 2>/dev/null || echo null)
      if [ -n "$current_model" ] && [ "$current_model" != "null" ]; then
        ollama stop "$current_model" 2>/dev/null || true
      fi
    fi

    install -d -m 0755 /run/ai-workstation
    printf '{"state":"gaming","provider":"openrouter","model":null,"updated":"%s"}\n' \
      "$(date -Iseconds)" > "$STATE_FILE"
    goose-state-sync || true
  '';

  # Does NOT restore a cached "previous" state — that's a stale-state trap
  # if the user undocked mid-game. Re-derives live eGPU presence and calls
  # the same NixOS-level sync services the hotplug hooks use, so the
  # docked/undocked model tags stay defined in exactly one place
  # (modules/nixos/apps/ai-workstation.nix), not duplicated here.
  aiWorkstationGamingStop = pkgs.writeShellScriptBin "ai-workstation-gaming-stop" ''
    set -euo pipefail
    # Deliberately excludes pkgs.sudo from this PATH: that's the raw,
    # non-setuid store binary, and since this PATH is prepended ahead of
    # the inherited one, it was shadowing /run/wrappers/bin/sudo (NixOS's
    # actual setuid wrapper) and made every invocation fail with "sudo:
    # ... must be owned by uid 0 and have the setuid bit set" — caught by
    # running this live, not by any build check. /run/wrappers/bin is on
    # every session's PATH already, so plain `sudo` below resolves to the
    # real wrapper via the inherited PATH tail instead.
    PATH=${lib.makeBinPath [ pkgs.pciutils ]}:$PATH

    # sudo's NOPASSWD command matching (modules/nixos/apps/ai-workstation.nix's
    # security.sudo.extraRules) is against the exact absolute systemctl path
    # in that rule, not just the resolved binary — a bare `systemctl` here
    # resolves to the identical binary via PATH but still silently falls
    # through to an interactive password/fingerprint prompt instead of
    # matching NOPASSWD. Confirmed live: bare form prompts, this exact
    # absolute path succeeds with no prompt.
    if lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      sudo ${pkgs.systemd}/bin/systemctl start ai-workstation-dock-sync.service
    else
      sudo ${pkgs.systemd}/bin/systemctl start ai-workstation-undock-sync.service
    fi
  '';

  gooseDesktopWrapped = pkgs.symlinkJoin {
    name = "goose-desktop";
    paths = [ pkgs.goose-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/goose-desktop \
        --run '${gooseStateSync}/bin/goose-state-sync || true'
    '';
  };

  # Everything below encodes what TODO.md §7's "Local coding-agent driver"
  # finding actually required to make Goose reliable for real coding work:
  # a fixed context length (see modules/nixos/services/ollama.nix), only
  # the `developer` extension loaded (Goose's full default extension set —
  # playwright/orchestrator/summon/etc — was measured live to bloat the
  # system+tool-schema prompt to ~15K tokens before the task even starts,
  # eating almost the entire context window), and a system prompt written
  # for a *small* model that has to compensate with process instead of
  # judgment (verify before declaring done, never fabricate a tool call,
  # investigate rather than guess). `qwen2.5-coder:14b` is hardcoded here
  # rather than following ai-workstation.nix's dock/undock routing — this
  # was only tested undocked/CPU-only (no eGPU attached this session), so
  # picking a docked-state model for this specific recipe is unverified
  # and deliberately deferred rather than guessed.
  codingAgentRecipe = ''
    version: 1.0.0
    title: "Local Coding Agent"
    description: "Claude-Code-style software engineering agent tuned for small local models."
    instructions: |
      You are a careful, disciplined software engineering agent running on a small
      local model. Because you are smaller than a frontier model, you must
      compensate with process, not improvisation.

      Core rules:
      - Always use your real tools to read files and run commands. Never write out
        what a tool call "would" return, and never print a tool call as text
        instead of invoking it for real.
      - Before making any change, read the actual file content first. Do not
        guess file contents from memory or from the task description.
      - Make the smallest change that correctly accomplishes the task. Do not
        refactor, rename, or "clean up" code that isn't part of the task.
      - Match the existing code style exactly (indentation, naming, comment
        density) rather than introducing your own conventions.
      - Do not add comments explaining what code does line by line. Only comment
        a genuinely non-obvious reason (a workaround, a subtle constraint).
      - After every edit, verify it: run the relevant build/check/test command if
        one is available (nix flake check, a linter, a test runner, or just
        re-reading the file back). Do not declare a task finished on faith.
      - If a tool call fails or a command errors, read the actual error message
        and fix the real problem. Retry with corrected input. Do not stop and ask
        a question if you can resolve it yourself with the tools you already
        have.
      - If you are asked to diagnose or investigate something, do real
        investigation: grep the codebase, read the relevant files in full, check
        installed library/type definitions on disk if relevant, and reason from
        what you actually find — not from a guess. State your confidence and
        what you verified vs. assumed.
      - For any destructive or hard-to-reverse action (deleting files, force
        operations, irreversible system changes), stop and describe what you
        want to do instead of doing it.
      - Keep your final answer concise: state what changed and why, referencing
        real file paths. Do not narrate your internal step-by-step process.
    prompt: "{{ task }}"
    parameters:
      - key: task
        input_type: string
        requirement: required
        description: "The task or question for the agent to work on"
    extensions:
      - type: builtin
        name: developer
        display_name: Developer
        timeout: 300
        bundled: true
      - type: platform
        name: todo
        display_name: Todo
        bundled: true
      - type: platform
        name: summon
        display_name: Summon
        bundled: true
      - type: platform
        name: orchestrator
        display_name: Orchestrator
        bundled: true
    settings:
      goose_provider: ollama
      goose_model: qwen2.5-coder:14b
  '';

  # One-shot task, then drops into an interactive follow-up session (`-s`,
  # confirmed compatible with `--recipe` live) — the closest local
  # equivalent to a Claude Code terminal session. Run from the directory
  # you want it to work in, same as `claude`/`goose run` itself.
  #
  # Bumps the power-profiles-daemon profile to `performance` for the
  # duration of the run and restores whatever it was before on exit —
  # found live that this laptop's `power-profiles-daemon` default
  # (`balanced`) caps sustained CPU inference well below its 4.7GHz max
  # (measured ~2.4GHz under load), and `performance` measurably improved
  # local-model token-generation speed with no `sudo` needed
  # (`powerprofilesctl` is user-callable). No `exec` here specifically so
  # the trap can still run after goose exits, success or not.
  #
  # Dock-aware model pick, independent of ai-workstation.nix's shared
  # dock/undock GOOSE_MODEL routing (deliberately not reused here — that
  # value also drives the general-assistant chat overlay, and the best
  # model for coding isn't necessarily the best model for quick chat).
  # Same `lspci -d 1002:73bf` eGPU-presence check ai-workstation-gaming-stop
  # already uses.
  #
  # Docked: primary/orchestrator is `qwen3.6:latest` (36B MoE, the more
  # general-reasoning model — real task breakdown/planning benefits from
  # its broader training more than a coder-specialized model's narrower
  # one), with `GOOSE_SUBAGENT_PROVIDER`/`GOOSE_SUBAGENT_MODEL` set to
  # `qwen3-coder:latest` so `Summon.delegate()` calls (enabled via the
  # recipe's `summon`/`orchestrator` extensions) hand actual code-writing
  # subtasks to the code-specialized model instead. Both env vars are set
  # here rather than as recipe `settings` keys since only
  # `goose_provider`/`goose_model` were confirmed as valid recipe setting
  # names via `goose recipe validate` — the subagent pair are documented
  # runtime env vars instead (see the "Goose capability upgrade" section
  # above). Verified live with the eGPU docked: `qwen3-coder:latest` (30B
  # MoE, code-specialized) offloads 78%/22% GPU/CPU (doesn't fully fit
  # 16GB VRAM at 20GB total) but still hits ~30-46 tok/s — comparable to
  # `qwen2.5-coder:14b`'s fully-GPU-offloaded ~37 tok/s — because MoE only
  # activates a fraction of its parameters per token.
  #
  # Undocked: no planner/coder split — CPU-only inference is slow enough
  # that juggling two different models (with their own separate load/evict
  # cycles) would cost more in reload latency than a split buys in
  # quality. `qwen2.5-coder:14b` alone remains the pick (the only one
  # proven reliable on CPU-only, see the driver-comparison finding above).
  gooseCode = pkgs.writeShellScriptBin "goose-code" ''
    set -uo pipefail
    PREV_PROFILE=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || echo balanced)
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance 2>/dev/null || true
    trap '${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$PREV_PROFILE" 2>/dev/null || true' EXIT

    if ${pkgs.pciutils}/bin/lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      MODEL=qwen3.6:latest
      export GOOSE_SUBAGENT_PROVIDER=ollama
      export GOOSE_SUBAGENT_MODEL=qwen3-coder:latest
    else
      MODEL=qwen2.5-coder:14b
    fi

    ${pkgs.goose-cli}/bin/goose run \
      --recipe "$HOME/.config/goose/recipes/coding-agent.yaml" \
      --provider ollama \
      --model "$MODEL" \
      --params task="$*" \
      -s
  '';
in
{
  home.packages = [
    pkgs.goose-cli
    pkgs.llmfit
    gooseStateSync
    aiWorkstationGamingStart
    aiWorkstationGamingStop
    gooseDesktopWrapped
    gooseCode
  ];

  home.file.".config/goose/recipes/coding-agent.yaml".text = codingAgentRecipe;

  # Only ensures the config *directory* exists — deliberately does not
  # seed a config.yaml with guessed provider/model keys. Run `goose
  # configure` interactively once to create it with a verified real
  # schema; goose-state-sync above no-ops until that file exists.
  home.activation.gooseConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.config/goose"
  '';
}
