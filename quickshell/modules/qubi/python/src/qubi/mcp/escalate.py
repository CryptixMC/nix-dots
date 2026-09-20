#!/usr/bin/env python3
"""escalate MCP server (stdio JSON-RPC) -- one tool, attached ONLY to the
engine's light tier (see qubi_engine.py's tier config generation).

The tool itself does nothing interesting: it just acknowledges and returns.
All the real work happens in qubi_engine.py, which watches the light tier's
`session/update` notification stream for a `tool_call` whose tool name is
`escalate`, pulls `reason`/`suggested_tier` back out of the call, and emits
its own `qubi/escalation_offer` notification to subscribed clients instead
of ever auto-switching tiers -- see docs/history/DECISIONS-2026-09-19.md, "the engine never
auto-escalates" is a hard invariant, not a default.

Same hand-rolled stdio MCP pattern as ask_user.py/notes_capture.py -- no new
dependency, no framework, just enough JSON-RPC to satisfy Goose's stdio
extension loader.
"""
import json
import sys

PROTOCOL_VERSION = "2024-11-05"

TOOL_DEF = {
    "name": "escalate",
    "description": (
        "Call this INSTEAD of answering when the task needs multi-file code "
        "changes, long/careful reasoning, or you would be guessing rather "
        "than confident. Do not bluff a hard answer -- escalate. For "
        "anything you can answer directly and confidently, just answer; "
        "do not call this for easy questions."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "reason": {
                "type": "string",
                "description": "One sentence: why this needs a bigger model.",
            },
            "suggested_tier": {
                "type": "string",
                "enum": ["heavy_local", "claude"],
                "description": "heavy_local for local multi-file/coding work; claude for anything needing broader judgment, ask_user, or wider tool access.",
            },
        },
        "required": ["reason", "suggested_tier"],
    },
}


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue

        method = req.get("method")
        req_id = req.get("id")

        if method == "initialize":
            send({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "escalate", "version": "1.0.0"},
                },
            })
        elif method == "notifications/initialized":
            pass
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": req_id, "result": {"tools": [TOOL_DEF]}})
        elif method == "tools/call":
            params = req.get("params", {})
            args = params.get("arguments", {})
            if params.get("name") != "escalate":
                send({
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32601, "message": f"Unknown tool: {params.get('name')}"},
                })
                continue
            # The real effect is the engine watching this call go by on the
            # session/update stream (see qubi_engine.py) -- this response is
            # just what the light-tier model sees as the tool's own result,
            # so it can naturally stop and wait rather than continuing to
            # try to answer itself.
            reason = args.get("reason", "")
            tier = args.get("suggested_tier", "heavy_local")
            send({
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{
                        "type": "text",
                        "text": f"Escalation offered to the user ({tier}: {reason}). Stop here and wait -- do not keep answering.",
                    }],
                },
            })
        elif req_id is not None:
            send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown method: {method}"}})


if __name__ == "__main__":
    main()
