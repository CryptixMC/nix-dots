"""Session registry: the client-facing conversation and its per-tier goose sessions."""
import asyncio
import json
import re
import time

from . import paths
from ._log import log

SAFE_ID = re.compile(r"^[A-Za-z0-9_.:-]+$")

# --------------------------------------------------------------------------
# Session registry + fan-out
# --------------------------------------------------------------------------

class Session:
    def __init__(self, session_id, tier):
        self.id = session_id
        self.tier = tier
        self.status = "idle"
        # Finer-grained than `status`, purely for the UI's activity
        # indicator. `status` says whether a turn is in flight; `phase` says
        # WHAT is taking the time, which is the difference between a panel
        # that looks frozen and one that looks busy. Measured on a real
        # docked turn: a trivial prompt spent ~16s with nothing at all sent
        # to the client, because the only two status pushes are "working" at
        # dispatch and "done" at the end. Every long-running step below now
        # names itself here instead.
        self.phase = "idle"
        # Short rolling description of what the model is reasoning about,
        # derived from the reasoning stream (first line of the newest
        # agent_thought_chunk, truncated). Deliberately NOT a second model
        # call -- summarising the summary would cost more than the turn.
        self.phase_detail = ""
        self.last_activity = time.monotonic()
        self.subscribers = set()  # ClientConn set
        self.last_user_prompt = None
        self.prompt_queue = []  # (ClientConn, params, respond_future)
        self.busy = False

        # One goose session per tier, because goose pins the model onto the
        # session row at session/new time:
        #   sessions.model_config_json = {"model_name": "qwen3:4b", ...}
        # session/load then RESTORES that pinned model, so the old design
        # (one goose session, session/load'ed onto whichever tier) silently
        # ran every tier on whatever model created the session. Proven by
        # unloading llama3.2 and watching a switch to the llama3.2-configured
        # `fast` tier never reload it -- it was still answering from qwen3.
        # Setting GOOSE_MODEL, the tier config's GOOSE_MODEL, and
        # providers.<p>.model all failed to override the pin.
        #
        # `self.id` stays the stable, client-facing id for the whole
        # conversation; these are the per-tier aliases the engine talks to
        # goose with. Clients never see them -- notifications are rewritten
        # back to self.id on the way out.
        self.tier_sessions = {tier: session_id}

        # Conversation to replay into the next tier's fresh goose session.
        # A brand-new session has no history, and escalation exists
        # precisely to hand a hard problem to a bigger model *with* its
        # context, so the transcript is carried over as a preamble on the
        # first prompt after a switch.
        self.pending_context = None

    def tier_sid(self, tier=None):
        """The goose session id to use when talking to `tier`."""
        t = tier or self.tier
        return self.tier_sessions.get(t, self.id)



class SessionsMixin:
    async def _new_session_on(self, tier_name):
        r = await self.tiers[tier_name].call("session/new", {"cwd": paths.default_cwd(self.cfg), "mcpServers": []})
        sid = r["result"]["sessionId"]
        sess = Session(sid, tier_name)
        self.sessions[sid] = sess
        self.session_by_alias[sid] = sess
        return sid, r

    def _register_alias(self, sess, tier_name, alias):
        sess.tier_sessions[tier_name] = alias
        self.session_by_alias[alias] = sess

    async def _bind_tier_session(self, sess, tier_name):
        """Ensure `sess` has a goose session on `tier_name`, creating one if
        needed, and return its alias.

        A fresh session/new (rather than session/load of the existing one) is
        the whole point: it is the only way the target tier's own model is
        the one that actually answers -- see Session.tier_sessions.
        """
        existing = sess.tier_sessions.get(tier_name)
        if existing:
            return existing
        tier = self.tiers[tier_name]
        r = await tier.call("session/new", {"cwd": paths.default_cwd(self.cfg), "mcpServers": []}, timeout=300)
        if r.get("error"):
            raise RuntimeError(f"session/new on {tier_name} failed: {r['error']}")
        alias = r["result"]["sessionId"]
        self._register_alias(sess, tier_name, alias)
        log(f"session {sess.id}: new goose session {alias} on tier {tier_name}")
        return alias

    async def _transcript_for(self, alias, limit=40):
        """Recent conversation from goose's own db, for replaying into a
        freshly-created session on another tier.

        Read from sessions.db rather than kept in memory because that is the
        system of record both this engine and Goose Desktop write to, and a
        session may predate this engine process entirely.
        """
        # A session can be vivified from a client-supplied id (qubi/subscribe),
        # so the alias is untrusted by the time it reaches this SQL string.
        if not isinstance(alias, str) or not SAFE_ID.match(alias):
            return None
        db_path = paths.GOOSE_SESSIONS_DB
        try:
            proc = await asyncio.create_subprocess_exec(
                "sqlite3", "-json", db_path,
                "SELECT role, content_json FROM (SELECT id, role, content_json FROM messages "
                f"WHERE session_id = '{alias}' ORDER BY id DESC LIMIT {limit}) ORDER BY id",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await proc.communicate()
            rows = json.loads(out.decode() or "[]")
        except Exception:
            return None
        lines = []
        for row in rows:
            try:
                parts = json.loads(row["content_json"])
            except Exception:
                continue
            if not isinstance(parts, list):
                continue
            body = "".join(p.get("text", "") for p in parts if p.get("type") == "text").strip()
            # Same synthetic scaffolding row SessionSync.qml filters: it is
            # injected context, not anything the human or model said.
            if not body or body.startswith("<turn-context>"):
                continue
            lines.append(f"{'User' if row['role'] == 'user' else 'Assistant'}: {body}")
        if not lines:
            return None
        return "\n".join(lines)

    async def _read_session_usage(self, session_id):
        """total_tokens/accumulated_total_tokens for a session, straight
        from goose's sessions.db. Only needed for the INITIAL number on a
        resumed session -- session/load's own result carries no usage
        field (confirmed live), unlike session/prompt's result, which
        already includes real usage data per turn and needs no help here.
        Same sqlite3 -json subprocess pattern _full_session_list already
        uses, just a single narrower query.
        """
        if not session_id:
            return {"totalTokens": 0, "accumulatedTotalTokens": 0}
        # Sum across every tier's goose session for this conversation, not
        # just the original id. Once a conversation switches tiers, the new
        # tier's tokens accrue against ITS session row, so querying only the
        # client-facing id would freeze the counter at whatever it read
        # before the switch.
        sess = self.sessions.get(session_id)
        ids = sorted(set(sess.tier_sessions.values())) if sess else [session_id]
        # session_id arrives straight off the wire (any ws client) and is
        # interpolated into SQL below -- sqlite3's CLI has no bind
        # parameters, so refuse anything that is not shaped like an id.
        ids = [i for i in ids if isinstance(i, str) and SAFE_ID.match(i)]
        if not ids:
            return {"totalTokens": 0, "accumulatedTotalTokens": 0}
        id_list = ", ".join(f"'{i}'" for i in ids)
        db_path = paths.GOOSE_SESSIONS_DB
        try:
            proc = await asyncio.create_subprocess_exec(
                "sqlite3", "-json", db_path,
                f"SELECT COALESCE(SUM(total_tokens), 0) AS totalTokens, "
                f"COALESCE(SUM(accumulated_total_tokens), 0) AS accumulatedTotalTokens "
                f"FROM sessions WHERE id IN ({id_list})",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await proc.communicate()
            rows = json.loads(out.decode() or "[]")
        except Exception:
            rows = []
        return rows[0] if rows else {"totalTokens": 0, "accumulatedTotalTokens": 0}

    async def _full_session_list(self):
        """Combines the engine's own live-known sessions with everything
        in Goose's SQLite that the engine didn't create (terminal `goose
        run`/`qubi-code` runs) -- Phase 2d's "complete even if some sessions
        bypass it" requirement."""
        live = {sid: {"session": sid, "tier": s.tier, "status": s.status, "live": True}
                for sid, s in self.sessions.items()}
        db_path = paths.GOOSE_SESSIONS_DB
        try:
            proc = await asyncio.create_subprocess_exec(
                "sqlite3", "-json", db_path,
                "SELECT id, working_dir, updated_at, goose_mode FROM sessions ORDER BY updated_at DESC LIMIT 50",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await proc.communicate()
            rows = json.loads(out.decode() or "[]")
        except Exception:
            rows = []
        for row in rows:
            sid = row["id"]
            if sid in live:
                continue
            live[sid] = {"session": sid, "tier": None, "status": "done", "live": False,
                        "workingDir": row.get("working_dir"), "updatedAt": row.get("updated_at")}
        return list(live.values())

    async def _switch_tier(self, sess, target_tier):
        """Move a conversation onto another tier.

        Binds (creating if necessary) a goose session on the target tier and
        queues the prior conversation for replay. Deliberately NOT
        session/load of the existing session: goose pins the model onto the
        session row at creation, so loading the old session onto a new tier
        keeps the OLD model answering -- which is why the `fast` tier was
        still running qwen3 despite every config key saying llama3.2.

        Re-entering a tier reuses that tier's existing goose session, so
        bouncing light -> heavy -> light does not spawn a session each time
        and the model still has its own side of the conversation.
        """
        previous_alias = sess.tier_sid()
        was_new = target_tier not in sess.tier_sessions
        await self._bind_tier_session(sess, target_tier)
        if was_new and previous_alias:
            # Fresh session on that tier => no memory of this conversation.
            sess.pending_context = await self._transcript_for(previous_alias)
        sess.tier = target_tier
