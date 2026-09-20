"""Tier notification handling: id rewriting, escalation offers, status/phase fan-out."""
import time

from ._log import log


class NotifyMixin:
    async def _on_tier_notification(self, tier_name, obj):
        method = obj.get("method")

        # Tier notifications are stamped with that tier's own goose session
        # alias. Resolve it back to the conversation and rewrite the id in
        # place, so a client that subscribed to session X keeps seeing X no
        # matter which tier is currently answering. Without this rewrite a
        # tier switch would silently orphan every subscriber.
        def _resolve(o):
            raw = o.get("params", {}).get("sessionId")
            s = self.session_by_alias.get(raw) or self.sessions.get(raw)
            if s is not None and raw != s.id:
                o["params"]["sessionId"] = s.id
            return s

        if method == "session/request_permission":
            sess = _resolve(obj)
            await self._broadcast_to_session(sess.id if sess else obj.get("params", {}).get("sessionId"), obj)
            return
        if method != "session/update":
            return
        upd = obj.get("params", {}).get("update", {})
        sess = _resolve(obj)
        sid = sess.id if sess else obj.get("params", {}).get("sessionId")
        kind = upd.get("sessionUpdate")

        if kind == "tool_call":
            tool_name = (upd.get("_meta", {}).get("goose", {}).get("toolCall", {}) or {}).get("toolName") or upd.get("title", "")
            if "escalate" in str(tool_name).lower() and sess is not None:
                raw = upd.get("rawInput") or {}
                reason = raw.get("reason", "the model requested a bigger tier")
                suggested = raw.get("suggested_tier", "heavy_local")
                sess.status = "awaiting_escalation"
                offer = {
                    "jsonrpc": "2.0",
                    "method": "qubi/escalation_offer",
                    "params": {
                        "session": sid,
                        "reason": reason,
                        "suggested_tier": suggested,
                        "options": ["escalate_claude", "escalate_heavy_local", "decline"],
                    },
                }
                await self._broadcast_to_session(sid, offer)
                log(f"session {sid}: escalation offered ({suggested}: {reason!r})")
                # Still forward the raw tool_call so a client-side transcript
                # can show it happened, same as any other tool call.
        if sess is not None:
            if kind in ("agent_message_chunk", "agent_thought_chunk", "tool_call", "tool_call_update"):
                sess.status = "working"
            # Name the sub-step so the indicator can distinguish "still
            # reasoning" from "writing the answer" from "running a tool" --
            # on a local reasoning model those are wildly different waits
            # (measured: 2652 chars of reasoning for a 20-char answer).
            if kind == "agent_thought_chunk":
                sess.phase = "reasoning"
                # Rolling detail derived from text already in hand -- no
                # second inference pass, because summarising the reasoning
                # with another model call would cost more than the turn it
                # describes.
                #
                # Accumulate first, THEN take the tail. Individual chunks are
                # far too small to be meaningful on their own: measured 1511
                # chars arriving as 374 chunks, i.e. ~4 chars each, so using
                # the chunk directly showed the user "Okay". Keeping only a
                # bounded tail of the buffer means this stays O(1) per chunk
                # rather than growing with the reasoning.
                chunk = (upd.get("content") or {}).get("text") or ""
                buf = (getattr(sess, "_reason_buf", "") + chunk)[-600:]
                sess._reason_buf = buf
                # Last sentence-ish fragment that is long enough to read.
                parts = [p.strip() for p in buf.replace("\n", " ").split(". ") if p.strip()]
                tail = next((p for p in reversed(parts) if len(p) > 25), parts[-1] if parts else "")
                if tail:
                    sess.phase_detail = tail[:110]
            elif kind == "agent_message_chunk":
                sess.phase = "responding"
                sess.phase_detail = ""
            elif kind in ("tool_call", "tool_call_update"):
                sess.phase = "tool"
                sess.phase_detail = str(
                    (upd.get("_meta", {}).get("goose", {}).get("toolCall", {}) or {}).get("toolName")
                    or upd.get("title", "")
                )[:110]
            sess.last_activity = time.monotonic()
        await self._broadcast_to_session(sid, obj)

    async def _broadcast_session_created(self, session_id, exclude=None):
        """Announce a newly created session to every other client.

        Deliberately fans out over self.clients rather than a session's
        subscriber set: the whole point is reaching clients that do NOT
        know this session exists yet, so there is nobody subscribed to
        target. A client that cares can follow up with qubi/subscribe.
        """
        sess = self.sessions.get(session_id)
        notif = {
            "jsonrpc": "2.0",
            "method": "qubi/session_created",
            "params": {
                "session": session_id,
                "tier": sess.tier if sess else "light",
            },
        }
        for c in list(self.clients):
            if c is exclude:
                continue
            await c.send(notif)

    async def _broadcast_to_session(self, session_id, obj):
        sess = self.sessions.get(session_id)
        targets = sess.subscribers if sess else self.clients
        for c in list(targets):
            await c.send(obj)
        await self._push_status(session_id)

    async def _push_status(self, session_id):
        sess = self.sessions.get(session_id)
        if not sess:
            return
        notif = {
            "jsonrpc": "2.0",
            "method": "qubi/session_status",
            "params": {
                "session": session_id,
                "status": sess.status,
                # Additive: older clients ignore unknown keys, so this is
                # safe to send unconditionally.
                "phase": getattr(sess, "phase", "idle"),
                "phaseDetail": getattr(sess, "phase_detail", ""),
                "tier": sess.tier,
                "lastActivity": sess.last_activity,
            },
        }
        for c in list(sess.subscribers):
            await c.send(notif)

    async def _set_phase(self, sess, phase, detail=None):
        """Name the current long-running step and tell the client immediately.

        Every call site is a place the engine used to go silent for seconds
        to minutes with no notification at all.
        """
        if sess is None:
            return
        sess.phase = phase
        if detail is not None:
            sess.phase_detail = detail
        await self._push_status(sess.id)
