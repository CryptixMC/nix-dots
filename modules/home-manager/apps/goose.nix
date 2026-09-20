{ pkgs, lib, config, ... }:

let
  # Reports dock/undock and gaming-eviction state changes via desktop
  # notification. Notification only, deliberately — it used to also push a
  # model switch into the chat overlay over its "qubi-model" IPC target,
  # which qubi-engine's arrival turned into an accidental tier switch (see
  # the long comment on the notify branches below). The engine watches the
  # same state file and handles model selection itself; config.yaml stays
  # Nix-generated and static (see gooseConfig below) either way.
  gooseStateSync = pkgs.writeShellScriptBin "qubi-state-sync" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.yq-go
        pkgs.hyprland
        # pkgs.quickshell dropped along with the switchModel call below --
        # nothing in this script shells out to quickshell any more.
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
      echo "[qubi-state-sync] no state file at $STATE_FILE yet — nothing to sync" >&2
      exit 0
    fi

    # -r unwraps the scalar to its raw form — without it, yq preserves the
    # double-quoted "style" tag from the JSON source and prints literal
    # quote characters as part of the string.
    state=$(yq -r '.state' "$STATE_FILE")
    provider=$(yq -r '.provider' "$STATE_FILE")

    # No `switchModel` call on any path any more -- notify only.
    #
    # This used to call `qubi-model switchModel "$provider" "$model"` for
    # docked and undocked. Pre-engine that meant literally "restart the
    # chat overlay's own goose acp with GOOSE_MODEL=$model", which is the
    # semantics ai-workstation.nix's dockedModel/undockedModel values were
    # picked for. qubi-engine owns those processes now, and
    # GooseAcpSession.switchModel is a thin shim that maps a model name
    # onto whichever TIER runs it (quickshell/modules/qubi/docs/history/BLOCKERS-2026-09-19.md #4). undockedModel is
    # qwen3-coder:latest, which is the HEAVY tier's model -- so every
    # undock was silently switching the live chat session from light to
    # heavy: an 18GB model on CPU, plus a whole different extension set
    # (losing `escalate`, gaining developer/searxng/fetch). Nobody asked
    # for a tier switch; the config value only ever meant "pick a model".
    #
    # Choosing which model a tier runs on CPU is the engine's job and it
    # does it itself now -- it watches this same state file and swaps the
    # light tier onto its `cpu_model` tag whenever the state is undocked or
    # gaming (qubi_engine.py's _hw_watch_loop). So there is nothing left
    # for this script to push; it just tells the user what changed.
    if [ "$state" = "gaming" ] || [ "$provider" = "null" ]; then
      hyprctl notify -1 4000 "rgb(89dceb)" "Gaming: local model evicted (chat overlay routing unchanged)" 2>/dev/null || true
    else
      hyprctl notify -1 4000 "rgb(89dceb)" "AI tier: $state — qubi switched to its $state models" 2>/dev/null || true
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
        pkgs.systemd
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
    qubi-state-sync || true

    # Runtime cgroup cap on ollama.service while gaming (Phase 5c) --
    # `set-property` edits the live cgroup, not the unit file, so this
    # never needs a switch and self-heals to nothing if this script is
    # never run again. AllowedCPUs=8-15 confines it to this i7-1260P's
    # 8 E-cores (confirmed via /sys/devices/system/cpu/cpu*/cpufreq/
    # cpuinfo_max_freq: cpu0-7 max at 4700MHz = the 4 P-cores/8 threads,
    # cpu8-15 max at 3400MHz = the 8 E-cores, no hyperthreading on E-cores)
    # -- the game's own threads keep the full P-core budget untouched.
    # CPUQuota=700% leaves one E-core-thread's worth of headroom for the
    # game/OS rather than saturating all 8. This is a SYSTEM unit, so it
    # needs the same scoped-NOPASSWD-for-one-exact-command pattern as
    # egpu-eject.service (modules/nixos/apps/ai-workstation.nix's own
    # sudo.extraRules) -- until Liam switches with that rule in place,
    # this line will prompt for a password (or fail non-interactively)
    # rather than silently no-op, which is the correct fail mode.
    sudo ${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota=700% AllowedCPUs=8-15 || \
      echo "[ai-workstation-gaming-start] cgroup cap failed (needs the ai-workstation.nix sudo rule + a switch) -- gaming proceeds without CPU/core isolation this time" >&2
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

    # Restores ollama.service's cgroup to its unit-file defaults (Phase
    # 5c) -- empty property values are systemd's documented way to reset
    # a runtime `set-property` override back to whatever the unit file
    # itself specifies, re-deriving rather than caching a "previous"
    # value, same rationale as the dock/undock state re-derivation just
    # above (don't trust a stale cached number either).
    sudo ${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota= AllowedCPUs= || \
      echo "[ai-workstation-gaming-stop] cgroup restore failed (needs the ai-workstation.nix sudo rule + a switch)" >&2
  '';

  # Wraps github-mcp-server with an auth token pulled from the
  # already-authenticated `gh` CLI session at invocation time (Part I's C6
  # already confirmed `gh auth token` succeeds non-interactively) rather
  # than a new secret. Only ever invoked if the model calls
  # manage_extensions to enable it — starts disabled in gooseConfig below.
  githubMcpServerWrapped = pkgs.writeShellScriptBin "github-mcp-server-wrapped" ''
    set -euo pipefail
    exec env GITHUB_PERSONAL_ACCESS_TOKEN="$(${pkgs.gh}/bin/gh auth token)" \
      ${pkgs.github-mcp-server}/bin/github-mcp-server stdio
  '';

  # Wraps mcp-searxng with SEARXNG_URL pointed at the local instance
  # (modules/nixos/services/searxng.nix) — self-hosted per explicit choice
  # over a public instance, so search queries never leave this machine.
  mcpSearxngWrapped = pkgs.writeShellScriptBin "mcp-searxng-wrapped" ''
    set -euo pipefail
    exec env SEARXNG_URL="http://127.0.0.1:8888" ${pkgs.mcp-searxng}/bin/mcp-searxng
  '';

  # Blocks `nh ... switch` inside a qubi-code session. Goose 1.47.0 has no
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
  # shadowing `nh` only inside qubi-code's own PATH (see the `export PATH`
  # in gooseCode below), never the user's interactive shell.
  # Validates every .qml file in quickshell/ with qmllint, restricted to the
  # one warning category that would have caught a real fatal-crash incident
  # this exists for: a boolean `anchors {}` block used on a plain
  # Rectangle/Item instead of PanelWindow's own special Anchors type,
  # producing "Invalid property assignment: unsupported type
  # QQuickAnchorLine" at Quickshell runtime load — a class of bug `nix
  # flake check` cannot see at all, since it only evaluates Nix
  # expressions, never QML. Every other qmllint warning category
  # (unqualified property access, uncreatable-type for Quickshell's own
  # C++-backed types like PanelWindow, and unresolved-type — the last one
  # false-positives repo-wide on legitimate Quickshell singletons like
  # JsonAdapter/BluetoothAdapter that a narrower single-file test didn't
  # happen to exercise) is disabled because it fires on this repo's real,
  # already-working QML and would make the gate useless — confirmed live
  # across all 49 real .qml files in this repo (clean exit 0) and against
  # the exact incident pattern reintroduced in a scratch file (reliably
  # exit 255, naming "Cannot assign literal of type bool to
  # QQuickAnchorLine") with exactly this flag set.
  qmlLintRepo = pkgs.writeShellScriptBin "qml-lint-repo" ''
    set -uo pipefail
    repo="''${1:-$HOME/nix-dots}"
    mapfile -t files < <(${pkgs.findutils}/bin/find "$repo/quickshell" -name '*.qml')
    if [ "''${#files[@]}" -eq 0 ]; then
      echo "qml-lint-repo: no .qml files found under $repo/quickshell" >&2
      exit 1
    fi
    ${pkgs.qt6.qtdeclarative}/bin/qmllint \
      -I ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
      -I ${pkgs.quickshell}/lib/qt-6/qml \
      --unqualified disable \
      --uncreatable-type disable \
      --incompatible-type error \
      --unresolved-type disable \
      "''${files[@]}"
  '';

  gooseNhGuard = pkgs.writeShellScriptBin "nh" ''
    set -euo pipefail
    for arg in "$@"; do
      if [ "$arg" = "switch" ]; then
        echo "[qubi-guard] 'nh ... switch' is blocked inside a qubi-code session — system/home activation stays human-gated. Stop and tell the user what you wanted to run instead." >&2
        exit 1
      fi
    done
    exec ${pkgs.nh}/bin/nh "$@"
  '';

  # Blocks `git commit`/`git push`/`git merge` inside any Goose-driven
  # session (CLI wrappers below AND Goose Desktop) -- a hard backstop, not
  # a mode setting the model has to remember to respect. Root-caused live
  # (2026-09-18, a real Goose Desktop session, `goose_mode: auto`,
  # provider ollama/qwen3-coder:latest, session "Quickshell UI redesign"
  # in sessions.db): asked to "discuss" a plan first, the model instead
  # went straight to editing files with no pause; told explicitly "I will
  # confirm what to merge to main", it merged AND pushed to origin/main on
  # its own three separate times across the session, never once showing a
  # diff for approval first. GOOSE_MODE=smart_approve (see gooseConfig
  # below) is the primary fix, but its "sensitive tool call" classifier is
  # Goose's own internal heuristic, not something this repo controls or
  # can verify classifies git commit/push as sensitive -- this guard makes
  # the block unconditional regardless of mode or model behavior, same
  # rationale as gooseNhGuard just above. Read-only git (status/diff/log/
  # branch/show/checkout for inspection) stays fully available -- the
  # model can still explore and report back, it just can't act
  # irreversibly without a human literally typing the command themselves.
  gooseGitGuard = pkgs.writeShellScriptBin "git" ''
    set -euo pipefail
    # Only the actual subcommand (the first positional arg) is checked --
    # not every arg -- so this doesn't false-positive on e.g.
    # `git log --grep=commit` or `git diff -- commit.txt`. Does NOT handle
    # `git -C dir commit` (a global flag taking its own value before the
    # subcommand) -- every real invocation observed in the actual incident
    # transcript was plain (`git commit -m ...`, `git push origin main`),
    # so this is a real, accepted, documented gap rather than a silently
    # incomplete parser -- revisit if a `-C`/`-c`-prefixed bypass is ever
    # seen in practice.
    subcommand=""
    for arg in "$@"; do
      case "$arg" in
        -*) continue ;;
        *) subcommand="$arg"; break ;;
      esac
    done
    case "$subcommand" in
      commit|push|merge)
        echo "[goose-guard] 'git $subcommand' is blocked inside a Goose-driven session (Desktop or a qubi-* wrapper) -- report the diff/plan and wait for the user to run it themselves, or ask them explicitly via ask_user first." >&2
        exit 1
        ;;
    esac
    exec ${pkgs.git}/bin/git "$@"
  '';

  # Backward-compat aliases for the pre-rebrand wrapper names — kept for
  # muscle memory, each just execs its renamed Qubi counterpart.
  qubiAliases = [
    (pkgs.writeShellScriptBin "goose-state-sync" ''exec ${gooseStateSync}/bin/qubi-state-sync "$@"'')
    (pkgs.writeShellScriptBin "goose-code" ''exec ${gooseCode}/bin/qubi-code "$@"'')
    (pkgs.writeShellScriptBin "goose-claude" ''exec ${gooseClaude}/bin/qubi-claude "$@"'')
    (pkgs.writeShellScriptBin "goose-plan" ''exec ${goosePlan}/bin/qubi-plan "$@"'')
    (pkgs.writeShellScriptBin "goose-chat" ''exec ${gooseChat}/bin/qubi-chat "$@"'')
  ];

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
        # Part II Stage 4: re-enabled. Goose's native progressive-disclosure
        # mechanism (search_available_extensions + manage_extensions,
        # confirmed live in the binary) — the heavy MCPs below stay
        # registered but disabled, costing only a name+description in
        # discovery until the model actually asks for one, instead of
        # paying their full tool-schema cost on every turn.
        enabled = true;
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
      # Enabled by default (unlike the other platform extensions above) --
      # Phase 4d's .agents/skills/ only does anything if a session actually
      # has this on. Confirmed live via `goose skills list` (no inference
      # needed, pure filesystem discovery) that Goose additively discovers
      # project-local .agents/skills/<name>/SKILL.md from CWD alongside the
      # global ~/.agents/skills/ ones already on this machine.
      skills = {
        enabled = true;
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

      # Part II Stage 4: registered but disabled — discoverable via
      # search_available_extensions/manage_extensions (extensionmanager
      # above) at only a name+description cost until actually enabled.
      # Fixes the old playwright entry's real GC-root time bomb too (it
      # previously lived outside any .nix file with zero GC roots).
      playwright = {
        enabled = false;
        type = "stdio";
        name = "playwright";
        display_name = "Playwright";
        description = "Browser automation for web testing, scraping, and interaction";
        cmd = "${pkgs.playwright-mcp}/bin/playwright-mcp";
        args = [ ];
        bundled = false;
        timeout = 60;
      };
      context7 = {
        enabled = false;
        type = "stdio";
        name = "context7";
        display_name = "Context7";
        description = "Up-to-date library and framework documentation lookup";
        cmd = "${pkgs.context7-mcp}/bin/context7-mcp";
        args = [ ];
        bundled = false;
        timeout = 60;
      };
      mcp-searxng = {
        enabled = false;
        type = "stdio";
        name = "mcp-searxng";
        display_name = "Web Search";
        description = "Private web search via a local, self-hosted SearXNG instance — needed for non-code chat questions requiring current information";
        cmd = "${mcpSearxngWrapped}/bin/mcp-searxng-wrapped";
        args = [ ];
        bundled = false;
        timeout = 60;
      };
      mcp-server-fetch = {
        enabled = false;
        type = "stdio";
        name = "mcp-server-fetch";
        display_name = "Fetch";
        description = "Fetch a URL and convert its content to readable text";
        cmd = "${pkgs.mcp-server-fetch}/bin/mcp-server-fetch";
        args = [ ];
        bundled = false;
        timeout = 60;
      };
      github-mcp-server = {
        enabled = false;
        type = "stdio";
        name = "github-mcp-server";
        display_name = "GitHub";
        description = "GitHub repository, issue, and pull request operations, authenticated via the existing gh CLI session";
        cmd = "${githubMcpServerWrapped}/bin/github-mcp-server-wrapped";
        args = [ ];
        bundled = false;
        timeout = 60;
      };
      # ask-user and notes-capture are not listed here: programs.qubi
      # (quickshell/modules/qubi/nix/hm-module.nix) merges them in, enabled
      # by default so they are reachable from any session.
    };
    providers = {
      ollama = {
        enabled = true;
        # Static fallback for any bare `goose run`/`goose acp` invocation
        # that doesn't go through qubi-code's dock-aware routing (cold
        # start, before ai-workstation-boot-sync's switchModel IPC call
        # lands). This is also the model any ACP client gets by default —
        # Goose Desktop's own "New Chat", and any qubi-engine
        # session that doesn't get an explicit --model override.
        #
        # qwen3:4b (2026-09-17 /goal speed target pick: 81.0 tok/s, 3/3 on
        # structured goose-bench tasks) was reverted 2026-09-18 after live
        # ACP testing found it genuinely unreliable on unstructured chat
        # input (hallucinated a file-write action / hung 40+s on a bare
        # "test" prompt, reproduced twice) in favor of qwen3.6:latest
        # (23GB, reliable but slow to cold-load and ~3x slower to
        # generate). Reverted back to qwen3:4b the same night, live, on
        # direct user instruction after actually using qwen3.6 as the
        # default and finding the load/generation time genuinely too slow
        # in practice — explicitly choosing speed over that measured
        # reliability margin, not an oversight. Also matches
        # ai-workstation.nix's dockedModel, which was qwen3:4b already
        # and had silently drifted inconsistent with this key. If ad-hoc
        # chat reliability regresses (hallucinated actions, hangs), that's
        # the known, accepted trade-off — see the git history on this
        # line for the qwen3.6 alternative and why it was tried. Coding
        # still explicitly overrides this in codingAgentRecipe below
        # (qwen3-coder:latest).
        model = "qwen3:4b";
        configured = true;
      };
      "claude-code" = {
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
    GOOSE_MODEL = "qwen3:4b";
    # See the model-choice comment above the "ollama" provider entry.
    # Thinking-off has no downside for casual/voice chat regardless of
    # which model is active, so this stays off unconditionally.
    GOOSE_LOCAL_ENABLE_THINKING = false;
    # Was unset (Goose's own internal default is "auto" -- confirmed live
    # via a real session/new call: availableModes lists auto/approve/
    # smart_approve/chat, and every session this repo has ever created
    # without an explicit override, Desktop included, came back
    # goose_mode: "auto"). "auto" grants blanket permission to every tool
    # call forever, no exceptions -- root-caused live as the direct cause
    # of a real incident (2026-09-18, Goose Desktop, session "Quickshell
    # UI redesign" in sessions.db): asked to discuss a plan first, it
    # edited files immediately with no pause; told explicitly "I will
    # confirm what to merge", it committed AND pushed to origin/main three
    # separate times with no approval step, ever. smart_approve ("ask only
    # for sensitive tool calls") is the safer default for every
    # Desktop/qubi-* session that doesn't explicitly override it --
    # GooseAcpSession.qml/GooseAcpPane.qml's own explicit
    # `"GOOSE_MODE": "auto"` for the interactive, human-supervised chat
    # overlay/compare pane still wins there (Process.environment overrides
    # the inherited env, confirmed elsewhere in this repo), so this change
    # only affects the *unsupervised* surfaces where nobody's watching
    # every turn in real time. gooseGitGuard (above) is the hard backstop
    # for git specifically, since smart_approve's "sensitive" classifier
    # is Goose's own internal heuristic, not something this repo can
    # verify actually flags git commit/push.
    GOOSE_MODE = "smart_approve";
  };

  gooseDesktopWrapped = pkgs.symlinkJoin {
    name = "goose-desktop";
    paths = [ pkgs.goose-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/goose-desktop \
        --prefix PATH : ${gooseGitGuard}/bin \
        --run '${gooseStateSync}/bin/qubi-state-sync || true'
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
      - You are running fully non-interactively. No human is watching this
        session or able to answer a question mid-run. Never end your turn by
        asking whether to proceed, offering a menu of options, or explaining
        how something works as if reporting to a reviewer — there is no one
        to respond, and the session will simply end unfinished. Reading a
        file to inform your task is not a request for your feedback on that
        file. Keep making progress on the actual task's deliverables until
        they exist, or you are genuinely blocked by one of the
        destructive/capability-exceeding cases below.
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
      - If a task exceeds your capability (needs broader reasoning, deep
        research, or repeated failed attempts), say so plainly and
        recommend the user run `qubi-claude <task>` to escalate to
        Claude Code. Never switch providers yourself.
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
      - type: stdio
        name: mcp-language-server
        display_name: MCP Language Server (nixd)
        cmd: ${pkgs.mcp-language-server}/bin/mcp-language-server
        args:
          - -lsp
          - ${pkgs.nixd}/bin/nixd
          - -workspace
          - /home/cryptix/nix-dots
        bundled: false
        timeout: 60
    settings:
      goose_provider: ollama
      goose_model: qwen3-coder:latest
      # Passes `goose recipe validate` but that validator doesn't enforce a
      # settings sub-schema (confirmed live: arbitrary unknown keys also
      # pass), so runtime effect is unconfirmed. Kept as a cheap, harmless
      # belt-and-suspenders alongside the confirmed-real GOOSE_MAX_TOKENS
      # env var qubi-code sets below — targets the truncation bug ("Tool
      # arguments for shell ... were truncated because the model reached
      # its output token limit").
      max_tokens: 4096
    # Confirmed valid live: `goose recipe validate` accepts this exact
    # shape (max_retries/checks/on_failure/timeout_seconds). On failure,
    # goose logs "Reset message history to initial state for retry" and
    # tries again — correct behaviour for a small model that talked itself
    # into a corner. Assumes CWD is the repo root being edited, same
    # assumption qubi-code's own doc comment already makes.
    retry:
      max_retries: 3
      checks:
        - type: shell
          command: "nix flake check"
        # Catches fatal QML runtime bugs nix flake check can't see (it only
        # evaluates Nix expressions) — e.g. the boolean anchors-on-Rectangle
        # incident that crashed the whole Quickshell shell and previously
        # required a human to find by reading Quickshell's own stdout log.
        - type: shell
          command: "qml-lint-repo"
      on_failure: "git checkout -- ."
      timeout_seconds: 900
  '';

  # Phase 4c: "research this and file it" — chains the two opt-in-disabled
  # search/fetch extensions with notes-capture (always-on, see the main
  # extensions block above). Recipes declare their own extensions list
  # independent of the main config's enabled flags (same pattern
  # codingAgentRecipe/mobileGuiAgentRecipe already establish), so
  # mcp-searxng/mcp-server-fetch being disabled by default globally doesn't
  # block them here. Invoke via `goose run --recipe
  # ~/.config/goose/recipes/research-agent.yaml --params topic="..."`.
  researchAgentRecipe = ''
    version: 1.0.0
    title: "Research and Capture"
    description: "Searches the local SearXNG instance and fetches real pages to research a topic, then files a structured summary via notes-capture."
    instructions: |
      You are a research agent. Given a topic or question, do real research
      and file a structured note about what you found -- do not answer from
      memory alone and do not skip the capture step.

      Process:
      1. Use searxng_web_search (or equivalent) to find several real,
         relevant sources for the topic. Do not fabricate URLs -- only use
         URLs a real search result actually returned.
      2. Fetch at least 2-3 of the most relevant results with your fetch
         tool and read their real content. Do not summarize a page you
         didn't actually fetch.
      3. Synthesize what you found into a concise summary, noting where
         sources disagree or something is unconfirmed.
      4. Call capture_note with a clear title, your summary, the real
         source URLs as links, and a few relevant tags. This is the
         required last step -- research that was never captured is
         incomplete, regardless of how good your final answer text is.

      You are running fully non-interactively -- no one is watching this
      session. Never end your turn asking whether to proceed; do the
      research and capture it, then stop.
    prompt: "{{ topic }}"
    parameters:
      - key: topic
        input_type: string
        requirement: required
        description: "The topic or question to research"
    extensions:
      - type: stdio
        name: mcp-searxng
        display_name: Web Search
        cmd: ${mcpSearxngWrapped}/bin/mcp-searxng-wrapped
        args: []
        bundled: false
        timeout: 60
      - type: stdio
        name: mcp-server-fetch
        display_name: Fetch
        cmd: ${pkgs.mcp-server-fetch}/bin/mcp-server-fetch
        args: []
        bundled: false
        timeout: 60
      - type: stdio
        name: notes-capture
        display_name: Notes Capture
        cmd: ${config.programs.qubi.goose.extensionCommands.notes-capture}
        args: []
        bundled: false
        timeout: 60
    settings:
      goose_provider: ollama
      goose_model: qwen3.6:latest
      max_tokens: 4096
  '';

  # A one-off variant of codingAgentRecipe with real browser control added
  # (playwright-mcp — normally kept out of the default recipe entirely
  # since its ~68 browser_* tools cost real tokens on every single
  # qubi-code invocation forever, see the "playwright" comment above).
  # Used for tasks that need to actually load a page and interact with it
  # to self-verify, not just read/write files — e.g. finishing and
  # packaging the mobile chat GUI, where the only real verification is
  # loading it in a browser and clicking through it. Not wired into any
  # permanent wrapper script; invoke directly with `goose run --recipe
  # ~/.config/goose/recipes/mobile-gui-agent.yaml`.
  mobileGuiAgentRecipe = ''
    version: 1.0.0
    title: "Local Coding Agent (browser-capable)"
    description: "Claude-Code-style software engineering agent tuned for small local models, with real browser control for self-testing web UIs."
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
      - You are running fully non-interactively. No human is watching this
        session or able to answer a question mid-run. Never end your turn by
        asking whether to proceed, offering a menu of options, or explaining
        how something works as if reporting to a reviewer — there is no one
        to respond, and the session will simply end unfinished. Reading a
        file to inform your task is not a request for your feedback on that
        file. Keep making progress on the actual task's deliverables until
        they exist, or you are genuinely blocked by one of the
        destructive/capability-exceeding cases below.
      - You have real browser control via your playwright tools. For any task
        involving a web page or HTML/JS file, do not declare it finished from
        reading the source alone: actually navigate to it, interact with it
        (click, fill, type) the way a real user would, and take a screenshot to
        confirm what actually renders and happens. Do not declare a UI feature
        working without having driven it through the browser at least once.
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
      - If a task exceeds your capability (needs broader reasoning, deep
        research, or repeated failed attempts), say so plainly and
        recommend the user run `qubi-claude <task>` to escalate to
        Claude Code. Never switch providers yourself.
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
      - type: stdio
        name: mcp-language-server
        display_name: MCP Language Server (nixd)
        cmd: ${pkgs.mcp-language-server}/bin/mcp-language-server
        args:
          - -lsp
          - ${pkgs.nixd}/bin/nixd
          - -workspace
          - /home/cryptix/nix-dots
        bundled: false
        timeout: 60
      - type: stdio
        name: playwright
        display_name: Playwright
        description: "Browser automation for web testing, scraping, and interaction"
        cmd: ${pkgs.playwright-mcp}/bin/playwright-mcp
        args: []
        bundled: false
        timeout: 60
    settings:
      goose_provider: ollama
      goose_model: qwen3-coder:latest
      max_tokens: 4096
    retry:
      max_retries: 3
      checks:
        - type: shell
          command: "nix flake check"
        - type: shell
          command: "qml-lint-repo"
      on_failure: "git checkout -- ."
      timeout_seconds: 1800
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
  # Undocked: same `qwen3-coder:latest` as the docked subagent, not the
  # retired `qwen2.5-coder:14b` — Part II's Stage 2 matrix (2026-09-16)
  # measured qwen2.5-coder at 0% real tool-calling success at any speed,
  # while qwen3-coder passed 5/6 tasks genuinely CPU-only (isolated
  # HIP_VISIBLE_DEVICES="" scratch instance), just slow (71-928s). No
  # planner/coder split undocked — CPU-only inference is slow enough that
  # juggling two models' separate load/evict cycles would cost more in
  # reload latency than a split buys in quality.
  #
  # GOOSE_LOCAL_ENABLE_THINKING=false: measured faster in every directly
  # comparable Stage 2 cell with no accuracy loss (e.g. 472s vs 679s
  # CPU-only on edit-verify) — qubi-code is the execution wrapper, thinking
  # stays reserved for qubi-plan below.
  gooseCode = pkgs.writeShellScriptBin "qubi-code" ''
    set -uo pipefail
    PREV_PROFILE=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || echo balanced)
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance 2>/dev/null || true
    trap '${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$PREV_PROFILE" 2>/dev/null || true' EXIT

    # Shadows `nh` (blocks `switch`) and `git` (blocks commit/push/merge)
    # for every process this session spawns (the developer extension's
    # shell tool inherits this PATH) — neither touches the interactive
    # shell's own PATH. See gooseGitGuard's own comment for the real
    # incident that motivated the git guard specifically.
    export PATH=${gooseNhGuard}/bin:${gooseGitGuard}/bin:$PATH

    # GOOSE_MAX_TOKENS: the confirmed-real fix for "Tool arguments for
    # shell ... were truncated because the model reached its output token
    # limit" (that log line's own sibling string names this exact fix).
    # Kept alongside the recipe's settings.max_tokens above since neither
    # was independently confirmed as the one goose actually reads.
    export GOOSE_MAX_TOKENS=4096
    export GOOSE_LOCAL_ENABLE_THINKING=false

    if ${pkgs.pciutils}/bin/lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      MODEL=qwen3.6:latest
      export GOOSE_SUBAGENT_PROVIDER=ollama
      export GOOSE_SUBAGENT_MODEL=qwen3-coder:latest
    else
      MODEL=qwen3-coder:latest
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

  gooseClaude = pkgs.writeShellScriptBin "qubi-claude" ''
    set -uo pipefail

    export PATH=${gooseGitGuard}/bin:$PATH
    export GOOSE_MAX_TOKENS=4096

    ${pkgs.goose-cli}/bin/goose run \
      --recipe "$HOME/.config/goose/recipes/coding-agent.yaml" \
      --provider claude-code \
      --params task="$*" \
      --max-turns 15 \
      --max-tool-repetitions 3 \
      -s
  '';

  # Dock-aware planner session. Reuses the same lspci eGPU detection as
  # gooseCode/docked branch (lspci -d 1002:73bf). Picks qwen3.6:latest
  # when docked; falls back to qwen3-coder:latest (not the retired
  # qwen2.5-coder:14b) for CPU-only invocations — same Stage 2 rationale as
  # gooseCode above. Thinking left at its default (on) here deliberately:
  # planning is exactly the role Part II's roster keeps thinking enabled
  # for, unlike qubi-code's execution wrapper.
  goosePlan = pkgs.writeShellScriptBin "qubi-plan" ''
    set -uo pipefail

    export PATH=${gooseGitGuard}/bin:$PATH
    export GOOSE_PLANNER_PROVIDER=ollama

    if ${pkgs.pciutils}/bin/lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      export GOOSE_PLANNER_MODEL=qwen3.6:latest
    else
      export GOOSE_PLANNER_MODEL=qwen3-coder:latest
    fi

    exec ${pkgs.goose-cli}/bin/goose session
  '';

  # Explicit, on-demand light chat wrapper for the gaming/quick-chat role —
  # deliberately separate from ai-workstation.nix's automatic dock/undock
  # routing, since "gaming" state there means "no model loaded" (VRAM
  # eviction, see aiWorkstationGamingStart above), not "a different model
  # auto-loaded". This is invoked by hand when the user actually wants to
  # ask something.
  #
  # Switched 2026-09-17 from gemma4:12b to qwen3:4b per the /goal speed
  # target. gemma4:12b was Stage 2's fastest pick (18-47s wall-clock) but
  # measured only 34.9 tok/s native generation despite 100% GPU residency —
  # traced to needing flash-attention for its quantized KV cache (confirmed
  # live: disabling FA to test an RDNA2-kernel-inefficiency theory instead
  # collapsed offload to 93% CPU and 2.77 tok/s — FA was never the problem).
  # qwen3:4b hits 81.0 tok/s at a smaller 4.0GB VRAM footprint (less game
  # impact) and passed 3/3 goose-bench tasks including the one gemma4:12b
  # failed (append-vs-overwrite) — a strict upgrade on every measured axis
  # for this role, at the cost of gemma4:12b's vision/audio capability,
  # which this chat/lookup role never used anyway.
  gooseChat = pkgs.writeShellScriptBin "qubi-chat" ''
    set -uo pipefail
    export PATH=${gooseGitGuard}/bin:$PATH
    export GOOSE_LOCAL_ENABLE_THINKING=false
    exec ${pkgs.goose-cli}/bin/goose session --provider ollama --model qwen3:4b
  '';
in
{
  home.packages = [
    pkgs.goose-cli
    pkgs.llmfit
    # sqlite3 CLI — goose itself stores session history in
    # ~/.local/share/goose/sessions/sessions.db (SQLite). Without this,
    # any qubi-code task that needs to inspect real session data (not
    # just Nix/QML files) fails with a bare "command not found" (exit
    # 127) the first time it reaches for sqlite3 — confirmed live: a
    # session investigating goose's session-storage format hit exactly
    # this and aborted with no working fallback.
    pkgs.sqlite
    gooseStateSync
    aiWorkstationGamingStart
    aiWorkstationGamingStop
    gooseDesktopWrapped
    gooseCode
    gooseClaude
    goosePlan
    gooseChat
    qmlLintRepo
    # SUPER+I screen-context capture's undocked/gaming OCR path
    # (ScreenContext.qml) -- not installed anywhere else in this flake.
    pkgs.tesseract
  ] ++ qubiAliases;

  # Everything below is fed to programs.qubi (quickshell/modules/qubi/nix/
  # hm-module.nix, enabled in ./qubi.nix), which owns the mechanism: writing
  # recipes, installing config.yaml as a real file with drift backup (Goose
  # rewrites it at runtime, so it can't be a store symlink), and merging in
  # Qubi's own ask-user/notes-capture extensions. This file only supplies
  # this machine's content.
  programs.qubi.goose = {
    manageConfig = true;
    settings = gooseConfig;

    recipes = {
      coding-agent = codingAgentRecipe;
      mobile-gui-agent = mobileGuiAgentRecipe;
      research-agent = researchAgentRecipe;
    };

    # Global counterpart to this repo's own AGENTS.md (repo root) — covers
    # a goose session invoked from outside this repo's directory, which the
    # project-level file wouldn't reach. Same content, single source of
    # truth via readFile rather than a second copy that could drift.
    extraInstructions = builtins.readFile ../../../AGENTS.md;
  };
}
