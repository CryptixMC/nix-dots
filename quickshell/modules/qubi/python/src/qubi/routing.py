"""Prompt routing: the heuristic pre-router and the per-session dispatch queue."""
import asyncio

from ._log import log

# --------------------------------------------------------------------------
# Heuristic pre-router (Phase 3a) -- zero-latency, pure string scoring, no
# model call. Deliberately conservative: only routes straight to "heavy" on
# strong syntactic signals (code fence, long message, explicit file path in
# a git repo). A moderate-length natural-language request that merely uses
# a word like "refactor" stays on light and relies on light's own judgment
# (the escalate tool) -- confirmed as the right split by Phase 0's own
# finding that tool-schema bloat, not tier choice, is the dominant latency
# cost, so keeping the default path light is worth a few hard prompts round-
# tripping through one escalate call.
# --------------------------------------------------------------------------

HEAVY_VERBS = ("refactor", "implement", "design", "migrate", "rewrite", "architect")


def score_prompt(text, cwd_is_git_repo=True):
    score = 0
    reasons = []
    if "```" in text:
        score += 5
        reasons.append("contains a code fence")
    if len(text) > 400:
        score += 3
        reasons.append(f"long message ({len(text)} chars)")
    if any(tok in text for tok in ("/home", "~/", "./")) and cwd_is_git_repo:
        score += 2
        reasons.append("mentions a file path")
    verb_hits = [v for v in HEAVY_VERBS if v in text.lower()]
    if verb_hits:
        score += 1
        reasons.append(f"verb signal: {verb_hits}")
    tier = "heavy" if score >= 5 else "light"
    return tier, score, reasons



class RoutingMixin:
    async def _dispatch_prompt(self, sess, text, client, req_id=None):
        # Route on the very first prompt only -- once a session has a real
        # tier bound (light by construction, or escalated), it stays there
        # until an explicit qubi/set_tier.
        if not getattr(sess, "_routed", False):
            tier_choice, score, reasons = score_prompt(text)
            sess._routed = True
            log(f"session {sess.id}: routed -> {tier_choice} (score={score}, {reasons})")
            if tier_choice == "heavy" and sess.tier != "heavy":
                # The worst silent gap in the whole engine: a cold heavy tier
                # means spawning `goose acp`, an initialize handshake and
                # loading a multi-GB model, all before the prompt is even
                # sent. Announce it instead of letting the panel sit blank.
                heavy_model = self.tiers["heavy"].tier_cfg.get("model", "heavy model")
                await self._set_phase(sess, "starting_model",
                                      f"loading {heavy_model} for a heavier request")
                await self.tiers["heavy"].ensure_started()
                # session/new on heavy, not session/load of the light
                # session -- loading would restore light's pinned model and
                # the "heavy" tier would answer as qwen3:4b.
                await self._switch_tier(sess, "heavy")

        if sess.busy:
            fut = asyncio.get_running_loop().create_future()
            sess.prompt_queue.append((client, text, req_id, fut))
            # Was "awaiting_permission", which is what a real permission
            # prompt uses -- a queued turn rendered as "awaiting permission"
            # in any UI that showed status verbatim. It is a queue, say so.
            sess.status = "queued"
            await self._set_phase(sess, "queued",
                                  "waiting for the current reply to finish")
            return await fut

        sess.busy = True
        sess.status = "working"
        sess.phase_detail = ""
        sess._reason_buf = ""
        await self._set_phase(sess, "thinking", "")
        # The alias can legitimately be missing here: a fresh ad hoc
        # "model:<tag>" tier from qubi/use_model has no session yet.
        # Rebinding lazily (rather than eagerly at switch time) means the
        # cost is paid on the next prompt, not on a settings click.
        if sess.tier not in sess.tier_sessions:
            await self.tiers[sess.tier].ensure_started(
                cpu_override=(sess.tier == "light" and self.cpu_only),
                extra_extensions=self._light_extras() if sess.tier == "light" else None)
            await self._bind_tier_session(sess, sess.tier)
        # Per-tier reasoning suppression. qwen3 narrates its reasoning as
        # ordinary content no matter what: GOOSE_LOCAL_ENABLE_THINKING=false
        # and Ollama's own think:false were both measured to only move that
        # text out of the `thinking` field and into the visible answer, and
        # neither makes the turn shorter. `/no_think` is the one switch that
        # measurably cuts generation (196 -> 104 tokens on the same prompt).
        # It is a property of the TIER, not a global: the fast tier wants it,
        # the heavy tier must never get it.
        #
        # Applied here, at the last moment before dispatch, because this is
        # the only place the outgoing prompt is built -- session/prompt is
        # the one ACP method the engine rebuilds from scratch rather than
        # forwarding verbatim, so anything a client attaches upstream is
        # discarded before it reaches this point.
        outgoing = text
        if self.tiers[sess.tier].tier_cfg.get("no_think_prefix"):
            outgoing = f"/no_think {text}"
        # First prompt after a tier switch: the target tier's goose session
        # is brand new and therefore has no memory of the conversation, so
        # replay it as a preamble. Consumed once.
        if sess.pending_context:
            # Fenced and explicitly labelled as reference material. An
            # earlier, looser wording ("here is the conversation so far …
            # continue it") made the model continue the *transcript* rather
            # than answer: a follow-up came back as "OKteal", echoing the
            # previous turn's "OK" before its actual answer.
            outgoing = (
                "[context from earlier in this conversation, handled by a different model]\n"
                "<<<TRANSCRIPT\n"
                f"{sess.pending_context}\n"
                "TRANSCRIPT>>>\n"
                "That transcript is background only -- do not repeat, quote or continue it.\n"
                f"Answer only this new message from the user:\n{outgoing}"
            )
            sess.pending_context = None
        try:
            r = await self.tiers[sess.tier].call("session/prompt", {
                "sessionId": sess.tier_sid(),
                "prompt": [{"type": "text", "text": outgoing}],
            }, timeout=300)
        except Exception as e:
            r = {"error": {"code": -32000, "message": str(e)}}
        sess.busy = False
        sess.status = "done" if "error" not in r else "error"
        await self._set_phase(sess, "done" if "error" not in r else "error", "")
        if req_id is not None:
            reply = {"jsonrpc": "2.0", "id": req_id}
            reply["error" if "error" in r else "result"] = r.get("error") or r.get("result")
            await client.send(reply)
        if sess.prompt_queue:
            next_client, next_text, next_req_id, next_fut = sess.prompt_queue.pop(0)
            asyncio.create_task(self._dispatch_prompt(sess, next_text, next_client, req_id=next_req_id))
            next_fut.set_result(None)
        return r
