{ pkgs, lib, ... }:

let
  # Reports dock/undock and gaming-eviction state changes via desktop
  # notification. Used to write GOOSE_PROVIDER/GOOSE_MODEL/providers.$p.model
  # into config.yaml via `yq -i` on every dock/undock — that's now neutered:
  # config.yaml is Nix-generated (see gooseConfig below) and this script's
  # writes would fight the activation-installed copy on every switch,
  # reintroducing the `providers.$p.model` dual-write hack and the `yq`
  # quoted-scalar bug class already paid for once. Live model routing for
  # dock/undock is Phase C4's job (env-var/profile selection per-invocation,
  # not a mutated shared config file); for now the chat overlay's model is
  # fixed by the Nix-generated config until that lands.
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

    # -r unwraps the scalar to its raw form — without it, yq preserves the
    # double-quoted "style" tag from the JSON source and prints literal
    # quote characters as part of the string.
    state=$(yq -r '.state' "$STATE_FILE")
    provider=$(yq -r '.provider' "$STATE_FILE")
    model=$(yq -r '.model' "$STATE_FILE")

    if [ "$state" = "gaming" ] || [ "$provider" = "null" ]; then
      hyprctl notify -1 4000 "rgb(89dceb)" "Gaming: local model evicted (config unchanged, routing is Nix-managed)" 2>/dev/null || true
    else
      hyprctl notify -1 4000 "rgb(89dceb)" "AI tier: $state ($model) — dock/undock model routing not yet wired (Phase C4)" 2>/dev/null || true
    fi
  '';

  # SUPER+G's gaming keybind (modules/home-manager/wm/hyprland.nix) wraps
  # gamescope launch with these two. Evicts the loaded model instantly via
  # `ollama stop` (no service restart needed, GPU stays physically bound)
  # Sends a desktop notification on entry so the user knows the model evicted,
  # while leaving config routing entirely untouched.
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
    printf '{"state":"gaming","provider":null,"model":null,"updated":"%s"}\n' \
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

  # Blocks `nh ... switch` inside a goose-code session. Goose 1.47.0 has no
  # native per-tool denylist/allowlist config key (checked live: `strings`
  # on the real binary at bin/.goose-wrapped has zero hits for
  # never_allow/allowlist/denylist/permission-anything — the only related
  # vocabulary is the interactive approve-mode decision set
  # approve/smart_approve/always_allow/allow_once/deny_once/always_deny,
  # which requires a TTY and doesn't exist as a config-file mechanism).
  # `nixos-rebuild switch` already can't run non-interactively — it needs
  # root and this system's only NOPASSWD sudo rules are the two dock/undock
  # sync services (modules/nixos/apps/ai-workstation.nix), so it would just
  # hang on a password prompt goose can't answer. `nh home switch` needs no
  # elevation at all, so it's the one command in the original never_allow
  # wishlist that was actually reachable — this wrapper closes that gap by
  # shadowing `nh` only inside goose-code's own PATH (see the `export PATH`
  # in gooseCode below), never the user's interactive shell.
  gooseNhGuard = pkgs.writeShellScriptBin "nh" ''
    set -euo pipefail
    for arg in "$@"; do
      if [ "$arg" = "switch" ]; then
        echo "[goose-guard] 'nh ... switch' is blocked inside a goose-code session — system/home activation stays human-gated. Stop and tell the user what you wanted to run instead." >&2
        exit 1
      fi
    done
    exec ${pkgs.nh}/bin/nh "$@"
  '';

  # Trimmed, Nix-generated replacement for the interactively-created
  # ~/.config/goose/config.yaml. This is what governs `goose acp` (the chat
  # overlay's backend) and any bare `goose run`/`goose session` — recipes
  # like codingAgentRecipe below declare their own `extensions:` list, which
  # *replaces* this set entirely for that invocation, so trimming here does
  # not affect the coding-agent recipe's summon/orchestrator/todo access.
  # Measured live: the untrimmed 18-extension config put `task.n_tokens` at
  # 15477 for a trivial "read this file" request against a 16384 context —
  # almost no room left for reasoning. Only developer+todo stay enabled;
  # code_execution stays permanently disabled (closed root-caused bug, see
  # "Corrections to earlier §7 conclusions" in the plan doc — a pre-execution
  # TypeScript type-check gate with no repair pass, not a missing runtime).
  # playwright is dropped entirely rather than disabled: 68 browser_* tools
  # is a major token cost even description-only, a browser isn't needed for
  # Nix work, and the live store path had zero GC roots (nix-collect-garbage
  # would silently kill it) — when browser work is needed later it belongs
  # in a dedicated recipe, not the global config.
  gooseConfig = {
    extensions = {
      developer = {
        enabled = true;
        type = "platform";
        name = "developer";
        description = "Write and edit files, and execute shell commands";
        display_name = "Developer";
        bundled = true;
      };
      todo = {
        enabled = true;
        type = "platform";
        name = "todo";
        description = "Enable a todo list for goose so it can keep track of what it is doing";
        display_name = "Todo";
        bundled = true;
      };
      computercontroller = {
        enabled = false;
        type = "builtin";
        name = "computercontroller";
        description = "General computer control tools that don't require you to be a developer or engineer.";
        display_name = "Computer Controller";
        timeout = 300;
        bundled = true;
      };
      extensionmanager = {
        enabled = false;
        type = "platform";
        name = "Extension Manager";
        description = "Enable extension management tools for discovering, enabling, and disabling extensions";
        display_name = "Extension Manager";
        bundled = true;
      };
      summarize = {
        enabled = false;
        type = "platform";
        name = "summarize";
        description = "Load files/directories and get an LLM summary in a single call";
        display_name = "Summarize";
        bundled = true;
      };
      tom = {
        enabled = false;
        type = "platform";
        name = "tom";
        description = "Inject custom context into every turn via GOOSE_MOIM_MESSAGE_TEXT and GOOSE_MOIM_MESSAGE_FILE environment variables";
        display_name = "Top Of Mind";
        bundled = true;
      };
      analyze = {
        enabled = false;
        type = "platform";
        name = "analyze";
        description = "Analyze code structure with tree-sitter: directory overviews, file details, symbol call graphs";
        display_name = "Analyze";
        bundled = true;
      };
      chatrecall = {
        enabled = false;
        type = "platform";
        name = "chatrecall";
        description = "Search past conversations and load session summaries for contextual memory";
        display_name = "Chat Recall";
        bundled = true;
      };
      scheduler = {
        enabled = false;
        type = "platform";
        name = "scheduler";
        description = "Create and manage scheduled recipe execution";
        display_name = "Scheduler";
        bundled = true;
      };
      skills = {
        enabled = false;
        type = "platform";
        name = "skills";
        description = "Discover and provide skill instructions from filesystem and builtins";
        display_name = "Skills";
        bundled = true;
      };
      summon = {
        enabled = false;
        type = "platform";
        name = "summon";
        description = "Load knowledge and delegate tasks to subagents";
        display_name = "Summon";
        bundled = true;
      };
      apps = {
        enabled = false;
        type = "platform";
        name = "apps";
        description = "Create and manage custom Goose apps through chat. Apps are HTML/CSS/JavaScript and run in sandboxed windows.";
        display_name = "Apps";
        bundled = true;
      };
      code_execution = {
        enabled = false;
        type = "platform";
        name = "code_execution";
        description = "Goose will make extension calls through code execution, saving tokens";
        display_name = "Code Mode";
        bundled = true;
      };
      orchestrator = {
        enabled = false;
        type = "platform";
        name = "orchestrator";
        description = "Manage agent sessions: list, view, start, send messages, interrupt, and stop agents";
        display_name = "Orchestrator";
        bundled = true;
      };
      autovisualiser = {
        enabled = false;
        type = "builtin";
        name = "autovisualiser";
        description = "Data visualization and UI generation tools";
        display_name = "Auto Visualiser";
        timeout = 300;
        bundled = true;
      };
      memory = {
        enabled = false;
        type = "builtin";
        name = "memory";
        description = "Teach goose your preferences as you go.";
        display_name = "Memory";
        timeout = 300;
        bundled = true;
      };
      tutorial = {
        enabled = false;
        type = "builtin";
        name = "tutorial";
        description = "Access interactive tutorials and guides";
        display_name = "Tutorial";
        timeout = 300;
        bundled = true;
      };
    };
    providers = {
      ollama = {
        enabled = true;
        model = "qwen2.5-coder:14b";
        configured = true;
      };
      "claude-acp" = {
        enabled = true;
        model = "";
        configured = true;
      };
    };
    active_provider = "ollama";
    GOOSE_TELEMETRY_ENABLED = false;
    OLLAMA_HOST = "localhost";
    GOOSE_TOOLSHIM_OLLAMA_MODEL = "qwen2.5-coder:7b";
    GOOSE_TOOLSHIM = false;
    GOOSE_PROVIDER = "ollama";
    GOOSE_MODEL = "qwen2.5-coder:14b";
  };

  gooseConfigYAML = lib.generators.toYAML { } gooseConfig;

  # A direct store path for the activation script to copy from — NOT the
  # same thing as the home.file entry below. Confirmed live:
  # `entryAfter [ "writeBoundary" ]` does NOT guarantee home.file's own
  # symlinks already exist — home-manager's actual activation order is
  # writeBoundary → gooseConfigInit → linkGeneration, so an activation
  # script depending on `home.file`'s live on-disk path fails with
  # "cannot stat ...: No such file or directory" on every switch. A plain
  # `pkgs.writeText` output is a build-time dependency instead, so it's
  # guaranteed to exist the moment the activation script runs, regardless
  # of file-linking order.
  gooseConfigFile = pkgs.writeText "goose-config.yaml" gooseConfigYAML;

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
      - Never run `git push`, `git reset --hard`, `rm -rf`, `nixos-rebuild
        switch`, or `nh ... switch`. These are irreversible or affect shared
        state beyond this repo. If your task seems to need one, stop and
        describe what you want to do instead of doing it.
      - For any other destructive or hard-to-reverse action, stop and
        describe what you want to do instead of doing it.
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
      - type: stdio
        name: mcp-nixos
        display_name: MCP NixOS
        cmd: ${pkgs.mcp-nixos}/bin/mcp-nixos
        args: []
        bundled: false
        timeout: 60
    settings:
      goose_provider: ollama
      goose_model: qwen2.5-coder:14b
      # Passes `goose recipe validate` but that validator doesn't enforce a
      # settings sub-schema (confirmed live: arbitrary unknown keys also
      # pass), so runtime effect is unconfirmed. Kept as a cheap, harmless
      # belt-and-suspenders alongside the confirmed-real GOOSE_MAX_TOKENS
      # env var goose-code sets below — targets the truncation bug ("Tool
      # arguments for shell ... were truncated because the model reached
      # its output token limit").
      max_tokens: 4096
    # Confirmed valid live: `goose recipe validate` accepts this exact
    # shape (max_retries/checks/on_failure/timeout_seconds). On failure,
    # goose logs "Reset message history to initial state for retry" and
    # tries again — correct behaviour for a small model that talked itself
    # into a corner. Assumes CWD is the repo root being edited, same
    # assumption goose-code's own doc comment already makes.
    retry:
      max_retries: 3
      checks:
        - type: shell
          command: "nix flake check"
      on_failure: "git checkout -- ."
      timeout_seconds: 900
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

    # Shadows `nh` with gooseNhGuard for every process this session spawns
    # (the developer extension's shell tool inherits this PATH) — refuses
    # `nh ... switch` without touching the interactive shell's own PATH.
    export PATH=${gooseNhGuard}/bin:$PATH

    # GOOSE_MAX_TOKENS: the confirmed-real fix for "Tool arguments for
    # shell ... were truncated because the model reached its output token
    # limit" (that log line's own sibling string names this exact fix).
    # Kept alongside the recipe's settings.max_tokens above since neither
    # was independently confirmed as the one goose actually reads.
    export GOOSE_MAX_TOKENS=4096

    if ${pkgs.pciutils}/bin/lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      MODEL=qwen3.6:latest
      export GOOSE_SUBAGENT_PROVIDER=ollama
      export GOOSE_SUBAGENT_MODEL=qwen3-coder:latest
    else
      MODEL=qwen2.5-coder:14b
    fi

    # --max-turns/--max-tool-repetitions confirmed real flags via
    # `goose run --help` (unlike GOOSE_MAX_TURNS, which was never
    # confirmed as an actual env var name) — small models loop.
    ${pkgs.goose-cli}/bin/goose run \
      --recipe "$HOME/.config/goose/recipes/coding-agent.yaml" \
      --provider ollama \
      --model "$MODEL" \
      --params task="$*" \
      --max-turns 15 \
      --max-tool-repetitions 3 \
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

  # Read-only oracle copy used below to detect runtime drift before
  # overwriting the live config.yaml. Not the live file itself — Goose
  # writes to config.yaml at runtime (`/model`, `/mode`, extension
  # enable/disable, `active_provider` — all go through
  # Config::{set_goose_model, set_goose_provider, set_param}, confirmed in
  # the goose_cli binary), and Home Manager store files are root-owned
  # read-only, so `home.file` can't target config.yaml directly.
  home.file.".config/goose/config.yaml.nix-source".text = gooseConfigYAML;

  # Installs the Nix-generated config.yaml over whatever's on disk on every
  # `home-manager switch`. If the live file has drifted from the *previous*
  # nix-source (i.e. Goose's own runtime writes changed it, e.g. a `/mode`
  # or `/model` switch from an interactive session), it's backed up first
  # rather than silently discarded — activation only overwrites, it never
  # merges.
  home.activation.gooseConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    configDir="$HOME/.config/goose"
    configFile="$configDir/config.yaml"
    nixSource="${gooseConfigFile}"

    run mkdir -p "$configDir"

    if [ -e "$configFile" ] && ! cmp -s "$configFile" "$nixSource" 2>/dev/null; then
      run cp "$configFile" "$configDir/config.yaml.pre-nix-$(date +%s)"
    fi

    run install -m 0644 "$nixSource" "$configFile"
  '';
}
