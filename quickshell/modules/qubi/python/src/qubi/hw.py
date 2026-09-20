"""Hardware state (docked / undocked / gaming) and what it changes.

The state file is an optional, documented interface -- see docs/hw-state.md.
With no file present the engine behaves as "docked": a GPU is available.
"""
import asyncio
import json

from . import paths
from ._log import log

# The two states with no GPU available for local inference. `gaming` means
# the eGPU is present but deliberately reserved for the game (Phase 5b);
# `undocked` means there is physically no eGPU at all. They differ in what
# else changes (see _hw_watch_loop) but they agree on the one thing that
# picks a model tag: inference lands on the CPU, so a tier's `cpu_model`
# is the correct tag rather than its GPU-tuned `model`.
CPU_ONLY_STATES = ("gaming", "undocked")
HW_STATES = ("docked", "undocked", "gaming")


def read_hw_state(path):
    try:
        with open(path) as f:
            state = json.load(f).get("state")
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        # No state file (or a torn write racing the producer's own
        # `> state.json`): assume docked, matching this engine's behaviour
        # before it knew about dock state at all.
        return "docked"
    return state if state in HW_STATES else "docked"


class HwMixin:
    @property
    def gaming(self):
        return self.hw_state == "gaming"

    @property
    def cpu_only(self):
        """True whenever local inference has no GPU to land on.

        Undocked was previously indistinguishable from docked here, so the
        light tier kept running its GPU-tuned tag (`qwen3:4b`) with no eGPU
        present -- Ollama silently fell back to CPU, which works, but skips
        the `qwen3:4b-cpu` tag that exists precisely to pin `num_gpu 0`
        rather than leave it to a fallback.
        """
        return self.hw_state in CPU_ONLY_STATES

    def _read_hw_state(self):
        return read_hw_state(paths.hw_state_file(self.cfg))

    def _light_extras(self):
        """Gaming-only additions to the light tier's extension list.

        Gated on `gaming`, NOT on `cpu_only`: the rationale (Phase 5d) is
        that game questions are usually web questions and a web lookup
        costs the game's own GPU/CPU nothing. Undocked shares the CPU-only
        model tag but none of that reasoning -- and undocked is exactly
        when an extra always-on stdio MCP server is least welcome.
        """
        if self.gaming and self.cfg.get("gaming", {}).get("searxng_on_light"):
            return ["mcp-searxng"]
        return None

    async def _hw_watch_loop(self):
        while True:
            await asyncio.sleep(2)
            new_state = self._read_hw_state()
            if new_state == self.hw_state:
                continue
            was_cpu_only = self.cpu_only
            was_extras = self._light_extras()
            self.hw_state = new_state
            log(f"hardware state changed -> {new_state}"
                f"{' (CPU-only inference)' if self.cpu_only else ''}")
            # Heavy tier is simply unavailable while gaming (Phase 5b) --
            # reap it now rather than waiting for its idle timer so it
            # can't be holding VRAM/CPU share mid-game. Gated on `gaming`
            # specifically, not on cpu_only: undocked, heavy is slow but
            # still legitimately usable (qwen3-coder:latest on CPU is the
            # documented undocked coding pick, see ai-workstation.nix), so
            # there is nothing to protect it from and no reason to kill it.
            if self.gaming:
                await self.tiers["heavy"].stop()
            # Only bounce the light tier if something it was actually
            # spawned with changed. undocked <-> gaming moves between two
            # CPU-only states where the model tag is identical, so without
            # this check a transition that changes neither the tag nor the
            # extension list would still drop every bound session's process
            # for nothing. Both inputs are compared, not just the tag:
            # undocked -> gaming keeps cpu_only True but does add searxng.
            if self.cpu_only == was_cpu_only and self._light_extras() == was_extras:
                continue
            # Restart the light tier under the new model tag -- any session
            # currently bound to light survives via session/load, same
            # mechanism as a manual tier switch.
            light = self.tiers["light"]
            bound_sessions = [s for s in self.sessions.values() if s.tier == "light"]
            # A dock/undock bounce stops and respawns the light tier under a
            # different model tag while sessions stay bound to it. Previously
            # every bound session just stalled with no notification at all.
            for sess in bound_sessions:
                await self._set_phase(
                    sess, "reloading_hardware",
                    "switching to CPU-only inference" if self.cpu_only else "switching to GPU inference")
            await light.stop()
            await light.ensure_started(cpu_override=self.cpu_only,
                                       extra_extensions=self._light_extras())
            for sess in bound_sessions:
                try:
                    # session/load is correct HERE (unlike a tier switch):
                    # this is the same tier being respawned, so the pinned
                    # model on the session row is the model we want back --
                    # only the process died. Uses the light tier's own alias.
                    await light.call("session/load", {"sessionId": sess.tier_sid("light"), "cwd": paths.default_cwd(self.cfg), "mcpServers": []})
                    await self._set_phase(sess, "idle", "")
                except Exception as e:
                    await self._set_phase(sess, "error", "failed to reload after a hardware change")
                    log(f"session {sess.id}: reload onto {'cpu' if self.cpu_only else 'gpu'} light tier failed: {e}")


def main():
    """qubi-hwstate: the one supported way for shell scripts to read the
    hardware state, so nothing outside this module parses the file."""
    import argparse
    import sys

    from . import config as qubi_config

    p = argparse.ArgumentParser(prog="qubi-hwstate")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("get", help="print docked | undocked | gaming")
    sub.add_parser("cpu-only", help="exit 0 if local inference has no GPU, else 1")
    sub.add_parser("path", help="print the state file path in use")
    args = p.parse_args()

    try:
        cfg = qubi_config.load()
    except (FileNotFoundError, ValueError):
        cfg = None
    path = paths.hw_state_file(cfg)
    if args.cmd == "path":
        print(path)
    elif args.cmd == "get":
        print(read_hw_state(path))
    else:
        sys.exit(0 if read_hw_state(path) in CPU_ONLY_STATES else 1)


if __name__ == "__main__":
    main()
