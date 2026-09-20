"""ACP passthrough: everything that is not `qubi/*` goes to a tier's goose, ids remapped."""
from ._log import log
from .sessions import Session


class AcpProxyMixin:
    async def _handle_acp_method(self, client, obj):
        method = obj.get("method")
        req_id = obj.get("id")
        params = obj.get("params", {}) or {}

        # Response to an agent-initiated request the client is answering
        # (session/request_permission) -- these carry no "method", just
        # id+result, so route by which session's tier issued that id...
        # simplification: for a permission response we forward to every
        # tier that has this session bound (there's exactly one), keyed by
        # session param the client should have echoed back. GooseAcpSession
        # .qml sends {id, result:{outcome:...}} with no sessionId in the
        # payload (see respondToPermission) -- so route using the session
        # currently subscribed for this client as the disambiguator.
        if method is None and ("result" in obj or "error" in obj):
            sid = next(iter(client.subscriptions), None)
            sess = self.sessions.get(sid) if sid else None
            if sess:
                self.tiers[sess.tier].send_raw(obj)
            return

        if method == "initialize":
            await client.send({"jsonrpc": "2.0", "id": req_id, "result": {
                "protocolVersion": 1,
                "agentCapabilities": {"loadSession": True},
                "agentInfo": {"name": "qubi-engine", "version": "1.0.0"},
            }})
            return

        if method == "session/new":
            sid, r = await self._new_session_on("light")
            client.subscriptions.add(sid)
            self.sessions[sid].subscribers.add(client)
            await client.send({"jsonrpc": "2.0", "id": req_id, "result": r["result"]})
            # Tell every OTHER connected client a session now exists.
            # Nothing else in the engine ever announces this -- broadcasts
            # are strictly subscriber-scoped and a brand-new session has
            # exactly one subscriber, so before this a second client could
            # only discover it by polling qubi/session_list.
            await self._broadcast_session_created(sid, exclude=client)
            return

        if method == "session/prompt":
            sid = params.get("sessionId")
            text = "".join(p.get("text", "") for p in params.get("prompt", []) if p.get("type") == "text")
            sess = self.sessions.get(sid)
            if sess is None:
                await client.send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32602, "message": "unknown session"}})
                return
            sess.last_user_prompt = text
            sess.subscribers.add(client)
            client.subscriptions.add(sid)
            await self._dispatch_prompt(sess, text, client, req_id=req_id)
            return

        # Every other ACP method (session/list, session/set_mode,
        # session/cancel, session/load, ...) forwards verbatim to whichever
        # tier the target session (if any) is bound to, defaulting to
        # light -- this is the "unchanged protocol" contract.
        sid = params.get("sessionId")
        sess = self.sessions.get(sid)
        tier_name = sess.tier if sess else "light"
        # Translate the client-facing id to the current tier's own goose
        # session alias. For a session that has never switched tiers these
        # are identical, so this is a no-op on the common path; after a
        # switch it is what keeps session/cancel, session/set_mode etc.
        # addressing the session the tier actually has open.
        if sess is not None and sess.tier_sid() != sid:
            params = dict(params)
            params["sessionId"] = sess.tier_sid()
        try:
            r = await self.tiers[tier_name].call(method, params)
            # session/load resumes a session the engine may know nothing
            # about (a DB row from a terminal run, or from before a
            # restart). Registering the caller as a subscriber here is
            # what makes a RESUMED session push notifications at all --
            # without it the client got nothing until it happened to send
            # its own first prompt, because only session/new and
            # session/prompt ever added a subscriber. Vivify a Session for
            # the id if needed, exactly as qubi/subscribe already does.
            if method == "session/load" and sid and not r.get("error"):
                if sess is None:
                    sess = Session(sid, tier_name)
                    self.sessions[sid] = sess
                    self.session_by_alias[sid] = sess
                sess.subscribers.add(client)
                client.subscriptions.add(sid)
                log(f"session {sid}: client subscribed via session/load")
            await client.send({"jsonrpc": "2.0", "id": req_id, "result": r.get("result"), "error": r.get("error")} if r.get("error") else {"jsonrpc": "2.0", "id": req_id, "result": r.get("result")})
        except Exception as e:
            await client.send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32000, "message": str(e)}})
