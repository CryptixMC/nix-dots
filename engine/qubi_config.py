#!/usr/bin/env python3
"""qubi-config: get/set/validate ~/.config/qubi/config.json.

This is Qubi's one runtime-mutable config file -- everything the engine, the
routing layer, and gaming behavior read at runtime lives here, NOT in a Nix-
generated file and NOT in env vars, specifically so Liam can edit it (by hand
or eventually via a settings UI) without a home-manager switch. Nix only ever
writes this file if it's missing (see qubi-engine.nix's activation snippet);
this CLI is the supported way to read/change it afterward.

Schema is intentionally small and flat-ish. `tiers` is the routing engine's
whole world: light (always-warm, minimal tools, chat default), heavy
(lazy-spawned, full tool surface, local reasoning/coding), claude (lazy-
spawned, claude-code provider). `gaming_budget` is an enum with exactly one
member tonight ("cpu") -- deliberately left as an enum, not a bool, because
Phase 5's own brief says future values (e.g. a small-model-on-iGPU budget)
are plausible later.
"""
import argparse
import copy
import json
import os
import sys

CONFIG_PATH = os.path.expanduser("~/.config/qubi/config.json")

# The only gaming_budget value implemented tonight. Kept as a list (not a
# single constant) so `validate` naturally extends when a second value is
# added later -- see Phase 5's brief: "leave the enum."
ALLOWED_GAMING_BUDGETS = ["cpu"]

DEFAULT_CONFIG = {
    "$schema_version": 1,
    "tiers": {
        # Below `light`: the tier the chat panel's thinking toggle routes to
        # when reasoning is switched OFF. Exists as a separate tier rather
        # than a flag on `light` because the only thing that actually makes
        # a qwen3 turn shorter is a prompt-level switch plus a smaller/terser
        # model, and both are per-tier settings -- see BLOCKERS.md on why
        # think:false and GOOSE_LOCAL_ENABLE_THINKING=false do not help.
        #
        # `no_think_prefix` prepends qwen3's documented `/no_think` switch.
        # It defaults to FALSE because measuring it here showed the opposite
        # of what BLOCKERS.md recorded -- against qwen3:4b through Ollama's
        # own /api/generate it DOUBLED the work rather than halving it
        # (716 -> 1440 eval tokens, 2704 -> 5366 chars of reasoning, same
        # prompt), because the model starts reasoning about the switch. The
        # option stays because it is a per-tier knob a different model may
        # honour properly; it is just not a win on qwen3.
        #
        # For the record, the other two levers were measured too and neither
        # gives a usable fast tier on qwen3:4b:
        #   think:true   1827 tokens  23.2s   7223 chars reasoning, 18 char answer
        #   think:false  1058 tokens  13.2s      0 chars reasoning, 4010 char answer
        # think:false is cheaper but relocates the reasoning into the answer
        # body, which is worse for a chat panel than a collapsed thought
        # bubble. The only real fix is a model that does not reason at all,
        # so point `model` at a small instruct model (llama3.2:3b,
        # qwen2.5:3b-instruct, gemma3:4b) to make this tier live up to its
        # name. Until then it behaves exactly like `light` minus extensions.
        "fast": {
            "provider": "ollama",
            # llama3.2:3b has no reasoning mode at all, which is the entire
            # point of this tier. Measured against qwen3:4b on the same
            # prompts: "what is 6 times 7" went 1827 tokens / 23.2s -> 2
            # tokens / 2.8s, and "name three Wayland compositors" 716 tokens
            # -> 13 tokens / 147ms, with zero reasoning characters both
            # times. The trade is accuracy: a 3B model is noticeably weaker
            # on facts (it answered that compositor question wrong), so this
            # tier is for speed-over-rigour, and anything that matters should
            # go to light/heavy.
            "model": "llama3.2:3b",
            "cpu_model": "llama3.2:3b",
            # No escalate extension: this tier exists to answer in one shot.
            # Every extension is another tool-call round trip.
            "extensions": [],
            "keep_alive": "-1",
            "warm_at_start": False,
            "idle_timeout_s": None,
            "no_think_prefix": False,
        },
        "light": {
            "provider": "ollama",
            "model": "qwen3:4b",
            "cpu_model": "qwen3:4b-cpu",
            "extensions": ["escalate"],
            "keep_alive": "-1",
            "warm_at_start": True,
            "idle_timeout_s": None,
        },
        "heavy": {
            "provider": "ollama",
            "model": "qwen3-coder:latest",
            "cpu_model": "qwen3-coder:latest",
            "extensions": [
                "developer",
                "ask-user",
                "notes-capture",
                "mcp-searxng",
                "mcp-server-fetch",
            ],
            "keep_alive": "8m",
            "warm_at_start": False,
            "idle_timeout_s": 480,
        },
        "claude": {
            "provider": "claude-code",
            # NOT "" -- confirmed live (Phase 4) that an empty/absent
            # GOOSE_MODEL makes `goose acp` fail session/new outright
            # ("Failed to resolve model: Configuration value not found:
            # GOOSE_MODEL") the moment the base config.yaml's own
            # top-level GOOSE_MODEL default isn't present to fall back on,
            # and even when it IS present, it leaks the wrong model
            # ("qwen3:4b") into a claude-code-provider session and every
            # prompt fails ("issue with the selected model (qwen3:4b)").
            # `claude --help` documents "sonnet"/"opus"/"fable" as valid
            # model aliases; "sonnet" confirmed working end-to-end live.
            "model": "sonnet",
            "cpu_model": "sonnet",
            "extensions": ["ask-user", "notes-capture"],
            "keep_alive": "8m",
            "warm_at_start": False,
            "idle_timeout_s": 480,
        },
    },
    "gaming_budget": "cpu",
    "escalation": {
        # The engine offers escalation via qubi/escalation_offer; it never
        # switches tiers on its own. Both flags exist so the "never auto"
        # invariant is a config fact a client can assert against, not just
        # an unwritten rule in the engine's code.
        "auto_offer": True,
        "auto_escalate_never": True,
    },
    "theme": "ultraviolet",
    "latency_budgets": {
        "light_ttft_ms": 1500,
        "heavy_ttft_ms": 8000,
    },
    "engine": {
        "socket_path": "$XDG_RUNTIME_DIR/qubi/engine.sock",
        "ws_host": "127.0.0.1",
        "ws_port": 8765,
    },
    "gaming": {
        "searxng_on_light": True,
    },
}


def load():
    with open(CONFIG_PATH) as f:
        return json.load(f)


def save(cfg):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    os.replace(tmp, CONFIG_PATH)


def _walk(cfg, dotpath, create=False):
    parts = dotpath.split(".")
    node = cfg
    for i, p in enumerate(parts[:-1]):
        if p not in node or not isinstance(node[p], dict):
            if create:
                node[p] = {}
            else:
                raise KeyError(dotpath)
        node = node[p]
    return node, parts[-1]


def cmd_get(args):
    cfg = load()
    if args.path is None:
        print(json.dumps(cfg, indent=2))
        return 0
    node, leaf = _walk(cfg, args.path)
    if leaf not in node:
        print(f"error: no such key {args.path!r}", file=sys.stderr)
        return 1
    val = node[leaf]
    print(json.dumps(val) if isinstance(val, (dict, list)) else val)
    return 0


def cmd_set(args):
    cfg = load()
    node, leaf = _walk(cfg, args.path, create=False)
    # Try JSON first (numbers, booleans, lists, null) so `set tiers.light.warm_at_start false`
    # stores a real bool, not the string "false"; fall back to plain string.
    try:
        value = json.loads(args.value)
    except json.JSONDecodeError:
        value = args.value
    node[leaf] = value
    errors = _validate(cfg)
    if errors:
        print("error: refusing to write, validation failed:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    save(cfg)
    print(f"{args.path} = {json.dumps(value)}")
    return 0


def _validate(cfg):
    errors = []
    if cfg.get("$schema_version") != 1:
        errors.append("$schema_version must be 1")
    tiers = cfg.get("tiers")
    if not isinstance(tiers, dict):
        errors.append("tiers must be an object")
    else:
        for name in ("light", "heavy", "claude"):
            t = tiers.get(name)
            if not isinstance(t, dict):
                errors.append(f"tiers.{name} missing or not an object")
                continue
            for key in ("provider", "model", "extensions", "keep_alive"):
                if key not in t:
                    errors.append(f"tiers.{name}.{key} missing")
            if "extensions" in t and not isinstance(t["extensions"], list):
                errors.append(f"tiers.{name}.extensions must be a list")
    gb = cfg.get("gaming_budget")
    if gb not in ALLOWED_GAMING_BUDGETS:
        errors.append(f"gaming_budget {gb!r} not in {ALLOWED_GAMING_BUDGETS}")
    esc = cfg.get("escalation", {})
    if not isinstance(esc, dict) or "auto_offer" not in esc or "auto_escalate_never" not in esc:
        errors.append("escalation.auto_offer / escalation.auto_escalate_never missing")
    if esc.get("auto_escalate_never") is not True:
        errors.append("escalation.auto_escalate_never must be true -- the engine must never auto-escalate")
    return errors


def cmd_validate(args):
    if not os.path.exists(CONFIG_PATH):
        print(f"error: {CONFIG_PATH} does not exist", file=sys.stderr)
        return 1
    try:
        cfg = load()
    except json.JSONDecodeError as e:
        print(f"error: invalid JSON: {e}", file=sys.stderr)
        return 1
    errors = _validate(cfg)
    if errors:
        for e in errors:
            print(f"FAIL: {e}")
        return 1
    print("OK: config valid")
    return 0


def cmd_init(args):
    """Write the default config, but only if nothing exists (or --force).
    This is what the home-manager activation snippet calls -- see
    qubi-engine.nix's home.activation.qubiConfigInit."""
    if os.path.exists(CONFIG_PATH) and not args.force:
        print(f"{CONFIG_PATH} already exists, not overwriting (use --force)")
        return 0
    save(copy.deepcopy(DEFAULT_CONFIG))
    print(f"wrote default config to {CONFIG_PATH}")
    return 0


def main():
    p = argparse.ArgumentParser(prog="qubi-config")
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("get", help="print the whole config, or one dotted key")
    g.add_argument("path", nargs="?", default=None)
    g.set_defaults(func=cmd_get)

    s = sub.add_parser("set", help="set one dotted key (JSON value if it parses, else raw string)")
    s.add_argument("path")
    s.add_argument("value")
    s.set_defaults(func=cmd_set)

    v = sub.add_parser("validate", help="check the config against the schema")
    v.set_defaults(func=cmd_validate)

    i = sub.add_parser("init", help="write the default config if missing")
    i.add_argument("--force", action="store_true")
    i.set_defaults(func=cmd_init)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
