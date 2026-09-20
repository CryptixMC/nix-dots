#!/usr/bin/env python3
"""qubi-models: roster / prune --dry-run for the Ollama model store.

Phase 7b. `roster` prints every model this repo actually declares a use
for -- both the engine's own tier config (~/.config/qubi/config.json,
read live, not hardcoded) and a small "extras" list of models referenced
by code elsewhere in the repo but outside the engine's own tier system
(grep-verified against the actual .nix/.qml source before being added
here, not guessed -- see each entry's own comment). `prune --dry-run`
diffs that against real `ollama list` output and reports what's present
but undeclared, with sizes. Never deletes anything -- Phase 7's own
instruction is dry-run only tonight.
"""
import argparse
import subprocess
import sys

from . import config as qubi_config

# Grep-verified against real source (not guessed) at the time this was
# written -- each entry names the file that actually references it, so a
# future re-check is a `grep`, not an archaeology project:
#   qwen3.6:latest      -- modules/home-manager/apps/goose.nix (qubi-code
#                          docked branch, qubi-plan docked branch: the
#                          "heavier reasoning" pick when docked)
#   qwen3-coder:latest  -- goose.nix (undocked default + docked subagent),
#                          modules/nixos/apps/ai-workstation.nix
#                          (undockedModel)
#   qwen3-vl:4b         -- quickshell/modules/screenctx/ScreenContext.qml
#                          (vision model for screen-context capture)
DECLARED_EXTRAS = {
    "qwen3.6:latest": "docked planner/heavy-chat model (goose.nix)",
    "qwen3-coder:latest": "undocked default + docked subagent model (goose.nix, ai-workstation.nix)",
    "qwen3-vl:4b": "screen-context vision model (ScreenContext.qml)",
}


def ollama_list():
    out = subprocess.run(["ollama", "list"], capture_output=True, text=True, check=True).stdout
    rows = []
    for line in out.splitlines()[1:]:  # skip header
        parts = line.split()
        if not parts:
            continue
        rows.append({"name": parts[0], "id": parts[1], "size": f"{parts[2]} {parts[3]}"})
    return rows


def declared_roster():
    cfg = qubi_config.load()
    roster = {}
    for tier_name, tier in cfg["tiers"].items():
        for key in ("model", "cpu_model"):
            m = tier.get(key)
            if m and tier["provider"] == "ollama":
                roster[m] = f"tiers.{tier_name}.{key} (~/.config/qubi/config.json)"
    for m, why in DECLARED_EXTRAS.items():
        roster.setdefault(m, why)
    return roster


def cmd_roster(args):
    roster = declared_roster()
    print(f"Declared roster ({len(roster)} models):")
    for m, why in sorted(roster.items()):
        print(f"  {m:28} {why}")
    return 0


def cmd_prune(args):
    if not args.dry_run:
        print("error: only --dry-run is implemented tonight (Phase 7b) -- "
              "real deletion needs a human running `ollama rm` themselves.",
              file=sys.stderr)
        return 1
    roster = declared_roster()
    installed = ollama_list()
    undeclared = [r for r in installed if r["name"] not in roster]
    print(f"Installed: {len(installed)} models. Declared roster: {len(roster)}. "
          f"Undeclared (prune candidates): {len(undeclared)}.\n")
    if not undeclared:
        print("Nothing to prune -- every installed model is declared somewhere in the repo.")
        return 0
    print("DRY RUN -- nothing deleted. To actually remove one of these, run:")
    for r in undeclared:
        print(f"  ollama rm {r['name']}   # {r['size']}, id {r['id']}")
    return 0


def main():
    p = argparse.ArgumentParser(prog="qubi-models")
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("roster", help="print the declared model roster")
    r.set_defaults(func=cmd_roster)

    pr = sub.add_parser("prune", help="list installed-but-undeclared models (dry-run only)")
    pr.add_argument("--dry-run", action="store_true", help="required tonight -- no real prune implemented")
    pr.set_defaults(func=cmd_prune)

    args = p.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
