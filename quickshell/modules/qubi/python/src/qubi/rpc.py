"""The `qubi/*` method namespace: handled by the engine, never forwarded to goose."""
import json
import os
import re

import yaml

from . import paths
from ._log import log
from .protocol import PROTOCOL, VERSION
from .sessions import Session
from .tier import TierProcess


class QubiMethodsMixin:
    async def _handle_qubi_method(self, client, obj):
        method = obj["method"]
        params = obj.get("params", {}) or {}
        req_id = obj.get("id")

        async def reply(result=None, error=None):
            if req_id is None:
                return
            msg = {"jsonrpc": "2.0", "id": req_id}
            msg["error" if error else "result"] = error or result
            await client.send(msg)

        if method == "qubi/status":
            await reply({
                # See protocol.py. Additive keys; older clients ignore them.
                "protocol": PROTOCOL,
                "version": VERSION,
                # `gaming` kept for existing clients that read it; `state`
                # and `cpuOnly` are the finer-grained truth (a client that
                # only looks at `gaming` cannot tell undocked from docked,
                # which is exactly the blind spot this engine had).
                "gaming": self.gaming,
                "state": self.hw_state,
                "cpuOnly": self.cpu_only,
                # Filtered to the persistent, named tiers -- self.tiers can
                # also hold ephemeral "model:<tag>" entries from
                # qubi/use_model, and those must never appear in a client's
                # tier-switch dropdown: they exist for one conversation's
                # direct model pick, not as a selectable, reusable tier.
                "tiers": {
                    n: {
                        "running": t.proc is not None and t.proc.returncode is None,
                        "ready": t.ready.is_set(),
                        "starting": t.starting,
                        "model": t.tier_cfg["cpu_model"] if (n == "light" and self.cpu_only) else t.tier_cfg["model"],
                    }
                    for n, t in self.tiers.items()
                    if n in self.cfg["tiers"]
                },
            })
        elif method == "qubi/theme":
            await reply(self._read_theme(params.get("name") or self.cfg.get("theme", "ultraviolet")))
        elif method == "qubi/session_list":
            await reply({"sessions": await self._full_session_list()})
        elif method == "qubi/subscribe":
            sid = params.get("session")
            sess = self.sessions.get(sid)
            if sess is None:
                sess = Session(sid, params.get("tier", "light"))
                self.sessions[sid] = sess
                self.session_by_alias[sid] = sess
            sess.subscribers.add(client)
            client.subscriptions.add(sid)
            await reply({"subscribed": sid})
        elif method == "qubi/set_tier":
            await self._set_tier(client, params.get("session"), params.get("tier"), reply)
        elif method == "qubi/installed_models":
            await reply({"models": await self._installed_models()})
        elif method == "qubi/use_model":
            await self._use_model(params.get("session"), params.get("model"), reply)
        elif method == "qubi/extensions":
            await reply(self._read_extensions())
        elif method == "qubi/session_usage":
            await reply(await self._read_session_usage(params.get("session")))
        else:
            await reply(error={"code": -32601, "message": f"unknown qubi method {method}"})

    async def _use_model(self, session_id, model, reply):
        """Switch ONE conversation onto a specific local model, right now,
        without touching any tier's persistent configuration.

        This is deliberately NOT the same operation as reassigning a named
        tier's model (that used to be `qubi/set_tier_model`, since removed):
        clicking a model in the browser's "use it now" flow must not mutate
        ~/.config/qubi/config.json or change what `light`/`fast`/`heavy`
        mean for every other session -- it should just answer the CURRENT
        conversation with the chosen model, same idea as picking a tier from
        the dropdown, except keyed by an exact model tag instead of a
        pre-configured tier name.

        Implemented as a synthetic, in-memory-only tier named `model:<tag>`,
        created on first use and reused by any session that picks the same
        model again. It never enters self.cfg["tiers"] and is therefore
        invisible to qubi_config.save(), to qubi/status's tier list (see the
        `n in self.cfg["tiers"]` filter there), and to a restart -- exactly
        the "ephemeral, not a replacement" behaviour asked for. Everything
        else (context replay across the switch, per-tier goose sessions so
        the right model actually answers, idle reaping) is the exact same
        generic machinery _switch_tier/_bind_tier_session already give every
        real tier -- see Session.tier_sessions' own header comment for why a
        fresh session/new per tier is required at all.
        """
        sess = self.sessions.get(session_id)
        if sess is None:
            await reply(error={"code": -32602, "message": f"unknown session {session_id}"})
            return
        if not model:
            await reply(error={"code": -32602, "message": "model is required"})
            return
        installed = {m["name"] for m in await self._installed_models()}
        if installed and model not in installed:
            await reply(error={"code": -32602, "message": f"{model} is not installed in Ollama"})
            return

        tier_key = f"model:{model}"
        if tier_key not in self.tiers:
            # No extensions: this path is for "answer me directly with this
            # model", not a tool-using session -- same reasoning as `fast`.
            self.tiers[tier_key] = TierProcess(tier_key, {
                "provider": "ollama",
                "model": model,
                "cpu_model": model,
                "extensions": [],
                "keep_alive": "-1",
                "warm_at_start": False,
                "idle_timeout_s": None,
                "no_think_prefix": False,
            }, self._on_tier_notification)

        await self.tiers[tier_key].ensure_started()
        old_tier = sess.tier
        try:
            await self._switch_tier(sess, tier_key)
        except Exception as e:
            await reply(error={"code": -32000, "message": f"switch to {model} failed: {e}"})
            return
        sess.status = "idle"
        await self._set_phase(sess, "idle", "")
        log(f"session {session_id}: using {model} directly (was {old_tier})")
        await reply({"session": session_id, "model": model})

    def _read_extensions(self):
        """Enabled-extension count + names, straight from goose's own
        config.yaml. Exists because a browser client (mobile_gui.html) has
        no filesystem access to read this the way the desktop QML client
        does (a direct `yq`/`cat` Process) -- this engine runs on the same
        host as the config file, so it can just read it and answer over
        the wire. Reuses the real yaml.safe_load already required for
        _read_theme-adjacent config reading (not JSON.parse/cat, which
        broke once before -- see qubi_engine.py's own history) rather than
        adding a second parsing path.
        """
        try:
            with open(paths.BASE_GOOSE_CONFIG) as f:
                cfg = yaml.safe_load(f) or {}
        except (FileNotFoundError, yaml.YAMLError):
            return {"enabledCount": 0, "extensions": []}
        extensions = cfg.get("extensions") or {}
        enabled = [
            {"key": k, "name": e.get("display_name") or e.get("name") or k}
            for k, e in extensions.items() if isinstance(e, dict) and e.get("enabled") is True
        ]
        enabled.sort(key=lambda e: e["name"])
        return {"enabledCount": len(enabled), "extensions": enabled}

    def _read_theme(self, name):
        theme_dir = os.path.join(paths.themes_dir(self.cfg), os.path.basename(name))
        tokens = {"name": name}
        b16_path = os.path.join(theme_dir, "base16.yaml")
        manifest_path = os.path.join(theme_dir, "theme.json")
        if os.path.exists(b16_path):
            # base16.yaml in this repo is plain `key: "hex"  # trailing
            # comment` lines (no nested structure, no leading "#" on the
            # hex itself) -- confirmed by reading the real file. A tiny
            # line parser avoids pulling in a YAML dependency for one flat
            # key:value file, but has to extract the *quoted* value
            # specifically rather than just splitting on ":" -- every real
            # line here has a trailing `# role description` comment, and a
            # bare .strip('"') only strips a quote character sitting at
            # the very start/end of the whole remainder, so it silently
            # left the comment text glued onto the value (confirmed live:
            # a mobile_gui.html theme application rendered a literal
            # `#050505"   # app background` as a CSS color before this
            # fix) instead of raising -- the exact kind of bug this
            # session's own discipline is to catch by testing live rather
            # than trusting a function compiled without error.
            base16 = {}
            with open(b16_path) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or ":" not in line:
                        continue
                    k, _, rest = line.partition(":")
                    m = re.search(r'"([^"]*)"', rest) or re.search(r"'([^']*)'", rest)
                    if m:
                        base16[k.strip()] = m.group(1)
            tokens["base16"] = base16
        if os.path.exists(manifest_path):
            with open(manifest_path) as f:
                tokens["manifest"] = json.load(f)
        return tokens

    async def _set_tier(self, client, session_id, target_tier, reply):
        sess = self.sessions.get(session_id)
        if sess is None:
            await reply(error={"code": -32602, "message": f"unknown session {session_id}"})
            return
        if target_tier not in self.tiers:
            await reply(error={"code": -32602, "message": f"unknown tier {target_tier}"})
            return
        target = self.tiers[target_tier]
        # Another silent gap: switching to a cold tier loads a model that can
        # take minutes, and the client previously got nothing until the reply
        # at the end of this function.
        await self._set_phase(sess, "switching_tier",
                              f"starting the {target_tier} tier "
                              f"({target.tier_cfg.get('model', '?')})")
        await target.ensure_started(cpu_override=(target_tier == "light" and self.cpu_only),
                                    extra_extensions=self._light_extras() if target_tier == "light" else None)
        old_tier = sess.tier
        try:
            await self._switch_tier(sess, target_tier)
        except Exception as e:
            await self._set_phase(sess, "error", "")
            await reply(error={"code": -32000, "message": f"switch to {target_tier} failed: {e}"})
            return
        sess.status = "idle"
        await self._set_phase(sess, "idle", "")
        log(f"session {session_id}: switched {old_tier} -> {target_tier}")
        await reply({"session": session_id, "tier": target_tier})
        if sess.last_user_prompt is not None:
            log(f"session {session_id}: re-sending last prompt to {target_tier}")
            await self._dispatch_prompt(sess, sess.last_user_prompt, client)
