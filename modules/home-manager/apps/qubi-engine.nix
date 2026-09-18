{ pkgs, lib, ... }:

let
  # engine/ (repo root, sibling to goose_bridge.py which it supersedes) is
  # tonight's new code: the runtime config CLI, the engine daemon itself
  # (Phase 2), and the escalate MCP server (Phase 3) all live there as
  # plain Python -- same "no build step, read straight from the repo"
  # choice goose_bridge.py already made, now shared by everything that
  # isn't QML. pythonEnv is the one place the `websockets` dependency is
  # declared; every script below that needs it shares this exact env so
  # there's no risk of one of them silently running against a bare
  # system python3 that lacks it (goose.nix's own gooseMobileBridge comment
  # already flagged this exact trap for goose_bridge.py).
  # pyyaml: ~/.config/goose/config.yaml is real block-style YAML, not the
  # JSON it happened to look like early in this build -- confirmed live
  # the hard way (engine crashed with a JSONDecodeError the first time
  # this file picked up genuinely non-flow-style content, e.g.
  # `providers.claude-code.model: Sonnet:5`, real runtime state Goose
  # itself had written back via a live `/model` change). JSON is a
  # syntactic subset of YAML, so this also transparently keeps working if
  # the file ever DOES happen to be flow-style/JSON-compatible again.
  pythonEnv = pkgs.python3.withPackages (p: [ p.websockets p.pyyaml ]);

  qubiConfigCli = pkgs.writeShellScriptBin "qubi-config" ''
    exec ${pythonEnv}/bin/python3 ${../../../engine/qubi_config.py} "$@"
  '';

  # Phase 7b -- shells out to `ollama list`, so needs it on PATH; PYTHONPATH
  # gets it engine/qubi_config.py's own declared-roster reading (same
  # "reads the real ~/.config/qubi/config.json, not a hardcoded copy"
  # discipline as everything else here).
  qubiModelsCli = pkgs.writeShellScriptBin "qubi-models" ''
    export PATH=${pkgs.ollama}/bin:$PATH
    export PYTHONPATH=${../../../engine}:$PYTHONPATH
    exec ${pythonEnv}/bin/python3 ${../../../engine/qubi_models.py} "$@"
  '';

  # Phase 9 -- talks JSON-RPC straight to the real engine socket (same
  # protocol GooseAcpSession.qml speaks), so needs no extra packages
  # beyond pythonEnv already has; PYTHONPATH gets it qubi_config.py's
  # `import qubi_config` (same reason qubiModelsCli needs it).
  qubiBenchCli = pkgs.writeShellScriptBin "qubi-bench" ''
    export PYTHONPATH=${../../../engine}:$PYTHONPATH
    exec ${pythonEnv}/bin/python3 ${../../../engine/qubi_bench.py} "$@"
  '';

  # QUBI_PY: engine/qubi_engine.py's build_tier_config_dir shells out to
  # this same interpreter (via the escalate extension's `cmd`) when
  # synthesizing the light tier's config -- see that function's own
  # comment. Passed as an env var rather than hardcoded so the escalate
  # tool always runs under the SAME python (with the same package set)
  # the engine itself runs under, not whatever bare `python3` happens to
  # resolve to on PATH at that moment.
  qubiEngineCli = pkgs.writeShellScriptBin "qubi-engine" ''
    export QUBI_PY="${pythonEnv}/bin/python3"
    cd ${../../../engine}
    exec ${pythonEnv}/bin/python3 -u qubi_engine.py
  '';
in
{
  home.packages = [
    qubiConfigCli
    qubiEngineCli
    qubiModelsCli
    qubiBenchCli
  ];

  # Writes ~/.config/qubi/config.json ONLY if it doesn't already exist --
  # this is the one config file in this whole repo that a `home-manager
  # switch` must NEVER clobber, because Phase 1's whole point is that Liam
  # (or a future settings UI) can edit tiers/routing/theme live without a
  # rebuild. Contrast gooseConfigInit in goose.nix, which unconditionally
  # overwrites config.yaml (backing up drift first) -- that file is meant
  # to stay Nix-authoritative; this one is meant to stay user-authoritative
  # after its first write. `qubi-config init` (not `--force`) already
  # implements the same no-clobber guard, so this activation snippet is a
  # one-line call into the same logic rather than a second implementation
  # of it.
  home.activation.qubiConfigInit = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${qubiConfigCli}/bin/qubi-config init
  '';

  # Replaces qubi-bridge.service (goose_bridge.py's old dumb single-
  # process relay) -- same WebSocket port (8765), same "always on for
  # mobile" role, but now backed by the real multi-tier engine instead of
  # one bare `goose acp` process. Restart=on-failure (not "always" -- a
  # crash-looping engine shouldn't hammer Ollama in a tight restart loop)
  # and After=graphical-session.target since it needs a live Hyprland
  # session for the same reasons goose-state-sync's own notify path does
  # (though the engine itself doesn't call hyprctl directly, its warm-up
  # Ollama call and tier processes assume a real user session is up).
  systemd.user.services.qubi-engine = {
    Unit = {
      Description = "Qubi engine: persistent multi-tier goose acp router (unix socket + websocket)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${qubiEngineCli}/bin/qubi-engine";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
