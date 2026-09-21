{ pkgs, lib, config, ... }:

let
  # Notifies on dock/undock/gaming state changes. Notification only --
  # qubi-engine watches the same state file and handles model selection
  # itself; config.yaml stays Nix-generated and static (see gooseConfig).
  gooseStateSync = pkgs.writeShellScriptBin "qubi-state-sync" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.yq-go
        pkgs.hyprland
      ]
    }:$PATH

    STATE_FILE=/run/ai-workstation/state.json

    # A login shell via `runuser ... bash -lc` doesn't inherit the desktop
    # session's env; rediscover it the way amd.nix's hyprctl_user() does.
    export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -n1)

    if [ ! -f "$STATE_FILE" ]; then
      echo "[qubi-state-sync] no state file at $STATE_FILE yet — nothing to sync" >&2
      exit 0
    fi

    # -r unwraps the scalar; without it yq keeps the JSON source's
    # double-quote style and prints literal quote characters.
    state=$(yq -r '.state' "$STATE_FILE")
    provider=$(yq -r '.provider' "$STATE_FILE")

    if [ "$state" = "gaming" ] || [ "$provider" = "null" ]; then
      hyprctl notify -1 4000 "rgb(89dceb)" "Gaming: local model evicted (chat overlay routing unchanged)" 2>/dev/null || true
    else
      hyprctl notify -1 4000 "rgb(89dceb)" "AI tier: $state — qubi switched to its $state models" 2>/dev/null || true
    fi
  '';

  # SUPER+G gaming keybind: evict the loaded model via `ollama stop`,
  # notify, write gaming state.
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

    # Confines ollama.service to the 8 E-cores while gaming (AllowedCPUs=8-15,
    # confirmed via cpuinfo_max_freq) so the game keeps the P-cores. Runtime
    # set-property, self-heals if this script never runs again. Needs the
    # matching NOPASSWD sudo rule in ai-workstation.nix.
    sudo ${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota=700% AllowedCPUs=8-15 || \
      echo "[ai-workstation-gaming-start] cgroup cap failed (needs the ai-workstation.nix sudo rule + a switch) -- gaming proceeds without CPU/core isolation this time" >&2
  '';

  # Re-derives live eGPU state and calls the same NixOS sync services the
  # hotplug hooks use, rather than restoring a cached "previous" state
  # (stale if the user undocked mid-game).
  aiWorkstationGamingStop = pkgs.writeShellScriptBin "ai-workstation-gaming-stop" ''
    set -euo pipefail
    # pkgs.sudo is the non-setuid store binary; keeping it out of PATH lets
    # the inherited /run/wrappers/bin/sudo (the real wrapper) resolve.
    PATH=${lib.makeBinPath [ pkgs.pciutils ]}:$PATH

    # sudo's NOPASSWD rule matches the exact absolute systemctl path, not
    # the resolved binary -- bare `systemctl` fails the match and prompts.
    if lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      sudo ${pkgs.systemd}/bin/systemctl start ai-workstation-dock-sync.service
    else
      sudo ${pkgs.systemd}/bin/systemctl start ai-workstation-undock-sync.service
    fi

    # Empty values reset set-property's runtime override to the unit file's
    # own defaults.
    sudo ${pkgs.systemd}/bin/systemctl set-property ollama.service CPUQuota= AllowedCPUs= || \
      echo "[ai-workstation-gaming-stop] cgroup restore failed (needs the ai-workstation.nix sudo rule + a switch)" >&2
  '';

  # Auth token pulled from the already-authenticated `gh` CLI session at
  # invocation time. Only runs if the model enables this extension itself.
  githubMcpServerWrapped = pkgs.writeShellScriptBin "github-mcp-server-wrapped" ''
    set -euo pipefail
    exec env GITHUB_PERSONAL_ACCESS_TOKEN="$(${pkgs.gh}/bin/gh auth token)" \
      ${pkgs.github-mcp-server}/bin/github-mcp-server stdio
  '';

  # Points at the local self-hosted SearXNG instance (services/searxng.nix)
  # so search queries never leave this machine.
  mcpSearxngWrapped = pkgs.writeShellScriptBin "mcp-searxng-wrapped" ''
    set -euo pipefail
    exec env SEARXNG_URL="http://127.0.0.1:8888" ${pkgs.mcp-searxng}/bin/mcp-searxng
  '';

  # Restricted to the one qmllint check that catches a real fatal-crash
  # class (bool `anchors {}` on a non-Anchors type) -- `nix flake check`
  # can't see this since it never evaluates QML. Other qmllint categories
  # false-positive across this repo's real, working QML.
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

  # Shadows `nh switch`/`nh ... switch` inside qubi-code's PATH -- Goose has
  # no native tool denylist, and this is the one privileged command it
  # could otherwise run without hitting a password prompt.
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

  # Hard backstop blocking git commit/push/merge in any Goose-driven session (Desktop or a
  # wrapper below) -- GOOSE_MODE alone isn't reliably enough to stop an unsupervised session
  # from pushing on its own. Read-only git stays available; the chat overlay's own interactive
  # session explicitly overrides GOOSE_MODE back to auto since a human is watching there.
  gooseGitGuard = pkgs.writeShellScriptBin "git" ''
    set -euo pipefail
    # Checks only the first non-flag arg, so `git log --grep=commit` etc.
    # aren't false positives. Doesn't handle `git -C dir commit` (a global
    # flag before the subcommand) -- no real invocation has needed it yet.
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

  # Back-compat aliases for the pre-rebrand wrapper names.
  qubiAliases = [
    (pkgs.writeShellScriptBin "goose-state-sync" ''exec ${gooseStateSync}/bin/qubi-state-sync "$@"'')
    (pkgs.writeShellScriptBin "goose-code" ''exec ${gooseCode}/bin/qubi-code "$@"'')
    (pkgs.writeShellScriptBin "goose-claude" ''exec ${gooseClaude}/bin/qubi-claude "$@"'')
    (pkgs.writeShellScriptBin "goose-plan" ''exec ${goosePlan}/bin/qubi-plan "$@"'')
    (pkgs.writeShellScriptBin "goose-chat" ''exec ${gooseChat}/bin/qubi-chat "$@"'')
  ];

  # Nix-generated replacement for goose's config.yaml. Recipes below
  # declare their own `extensions:` list, replacing this set entirely per
  # invocation, so trimming here doesn't affect the coding recipes' summon/
  # orchestrator/todo access. Measured: the untrimmed 18-extension set cost
  # ~15K of a 16384-token context before the task even started -- only
  # developer+todo stay on. code_execution stays off (closed bug: a
  # pre-execution type-check gate with no repair pass). playwright is
  # dropped rather than disabled -- 68 tools is real token cost and it
  # belongs in a dedicated recipe, not the global config.
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
        # Goose's native progressive-disclosure mechanism
        # (search_available_extensions + manage_extensions) -- the disabled
        # extensions below cost only a name+description in discovery until
        # actually requested.
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
      # On by default (unlike the other platform extensions) so
      # .agents/skills/ actually gets used -- Goose additively discovers
      # project-local SKILL.md files from CWD alongside the global ones.
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
      # Registered but disabled -- discoverable via extensionmanager at
      # low cost.
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
      # ask-user/notes-capture aren't listed here -- the qubi flake's own
      # home-manager module merges them in, enabled by default.
    };
    providers = {
      ollama = {
        enabled = true;
        # Fallback for any invocation outside qubi-code's dock-aware
        # routing (cold start, bare `goose run`/`goose acp`, Goose
        # Desktop's New Chat). qwen3:4b chosen for speed over the more
        # reliable but much slower qwen3.6:latest; matches
        # ai-workstation.nix's dockedModel. Coding recipes override this
        # explicitly.
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
    GOOSE_LOCAL_ENABLE_THINKING = false;
    # smart_approve, not Goose's "auto" default -- "auto" grants blanket tool permission with
    # no approval step, unsafe for unsupervised sessions. The chat overlay's own interactive
    # session overrides this back to auto since a human is watching there. gooseGitGuard above
    # is the hard backstop regardless, since smart_approve's "sensitive" classifier is unverified.
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

  # Tuned per the coding-driver findings in qubi's development log: fixed
  # context length (see nixos/services/ollama.nix), only the `developer`
  # extension (the full default set bloats the prompt to ~15K tokens before
  # the task starts), and a system prompt written for a small model that
  # has to compensate with process over judgment. Model is hardcoded, not
  # dock-aware -- only verified undocked/CPU-only.
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
      # Unenforced by `goose recipe validate` (arbitrary keys pass), but
      # harmless alongside the confirmed-real GOOSE_MAX_TOKENS env var
      # qubi-code sets -- both target the truncation bug ("Tool arguments
      # for shell ... were truncated because the model reached its output
      # token limit").
      max_tokens: 4096
    # max_retries/checks/on_failure/timeout_seconds confirmed valid via
    # `goose recipe validate`. On failure, goose resets message history and
    # retries -- correct for a small model that talked itself into a
    # corner. Assumes CWD is the repo root being edited.
    retry:
      max_retries: 3
      checks:
        - type: shell
          command: "nix flake check"
        # Catches fatal QML runtime bugs nix flake check can't see.
        - type: shell
          command: "qml-lint-repo"
      on_failure: "git checkout -- ."
      timeout_seconds: 900
  '';

  # Chains the search/fetch extensions with notes-capture (always-on) to
  # research a topic and file a structured note. Invoke via `goose run
  # --recipe ~/.config/goose/recipes/research-agent.yaml --params topic=...`.
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

  # codingAgentRecipe + playwright, for tasks needing real browser
  # verification (e.g. a web UI) -- playwright stays out of the default
  # recipe since its ~68 tools cost real tokens on every invocation.
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

  # One-shot task then an interactive follow-up (-s) -- the closest local
  # equivalent to a Claude Code terminal session. Bumps power-profiles-daemon
  # to `performance` for the run (measured: `balanced` caps sustained CPU
  # inference well below the 4.7GHz max) and restores it on exit; no `exec`
  # so the trap can still run after goose exits. Dock-aware model pick,
  # independent of ai-workstation.nix's routing (which also drives the
  # general chat overlay -- the best coding model isn't necessarily the
  # best chat model). Docked: qwen3.6:latest as planner/orchestrator, with
  # Summon.delegate() calls handed to qwen3-coder:latest as subagent.
  # Undocked: qwen3-coder:latest alone (qwen2.5-coder measured 0% real
  # tool-calling success; no planner/coder split -- CPU-only load/evict
  # cycles would cost more than a split buys). Thinking off: measured
  # faster with no accuracy loss.
  gooseCode = pkgs.writeShellScriptBin "qubi-code" ''
    set -uo pipefail
    PREV_PROFILE=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get 2>/dev/null || echo balanced)
    ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance 2>/dev/null || true
    trap '${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$PREV_PROFILE" 2>/dev/null || true' EXIT

    # Shadows nh (blocks switch) and git (blocks commit/push/merge) for
    # every process this session spawns; never touches the interactive
    # shell's own PATH.
    export PATH=${gooseNhGuard}/bin:${gooseGitGuard}/bin:$PATH

    # Confirmed-real fix for "Tool arguments for shell ... were truncated
    # because the model reached its output token limit".
    export GOOSE_MAX_TOKENS=4096
    export GOOSE_LOCAL_ENABLE_THINKING=false

    if ${pkgs.pciutils}/bin/lspci -d 1002:73bf 2>/dev/null | grep -q .; then
      MODEL=qwen3.6:latest
      export GOOSE_SUBAGENT_PROVIDER=ollama
      export GOOSE_SUBAGENT_MODEL=qwen3-coder:latest
    else
      MODEL=qwen3-coder:latest
    fi

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

  # Dock-aware planner session (same eGPU check as gooseCode). Thinking
  # stays on here, deliberately -- planning is the role that benefits from
  # it, unlike qubi-code's execution wrapper.
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

  # On-demand quick-chat wrapper, separate from ai-workstation.nix's
  # automatic routing (gaming state there means no model loaded, not a
  # different one auto-loading). qwen3:4b: fastest tested model that still
  # passes goose-bench's append-vs-overwrite check.
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
    # sqlite3 CLI -- goose stores session history in
    # ~/.local/share/goose/sessions/sessions.db; qubi-code tasks that
    # inspect it need this on PATH.
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
    # (ScreenContext.qml, in the qubi repo) -- not installed elsewhere.
    pkgs.tesseract
  ] ++ qubiAliases;

  # Fed to programs.qubi (the qubi flake's home-manager module), which owns
  # the mechanism: writing recipes, installing config.yaml as a real file
  # with drift backup, and merging in Qubi's own ask-user/notes-capture
  # extensions. This file only supplies this machine's content.
  programs.qubi.goose = {
    manageConfig = true;
    settings = gooseConfig;

    recipes = {
      coding-agent = codingAgentRecipe;
      mobile-gui-agent = mobileGuiAgentRecipe;
      research-agent = researchAgentRecipe;
    };

    # Global counterpart to this repo's own AGENTS.md, for sessions invoked
    # outside this repo's directory.
    extraInstructions = builtins.readFile ../../../AGENTS.md;
  };
}
