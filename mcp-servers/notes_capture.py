#!/usr/bin/env python3
"""notes-capture MCP server (stdio JSON-RPC).

Exposes one tool, capture_note(title, summary, links, tags), that appends a
structured Markdown entry to the capture target. Also driven directly by
the SUPER+N Quickshell overlay (same file-append, not a second code path)
for the manual "jot this down right now" case, not just research-recipe use.

Target: .agents/inbox.md, not the user's real Obsidian vault
(~/Documents/Vault, confirmed real -- see DECISIONS.md for why this default
was picked and how to redirect it). Flagged low-confidence there
deliberately -- change VAULT_PATH below once Liam says where captures
should actually land.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

VAULT_PATH = os.path.expanduser("~/nix-dots/.agents/inbox.md")

PROTOCOL_VERSION = "2024-11-05"

TOOL_DEF = {
    "name": "capture_note",
    "description": "Append a structured note entry (title, summary, links, tags) to the capture inbox. Use to save research findings, ideas, or anything worth remembering outside the current conversation.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "summary": {"type": "string"},
            "links": {"type": "array", "items": {"type": "string"}},
            "tags": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["title", "summary"],
    },
}


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def capture_note(title, summary, links, tags):
    os.makedirs(os.path.dirname(VAULT_PATH), exist_ok=True)
    date = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M")

    lines = [f"## {title}", "", f"*{date}*", "", summary.strip(), ""]
    if links:
        lines.append("**Links:**")
        lines.extend(f"- {link}" for link in links)
        lines.append("")
    if tags:
        lines.append(" ".join(f"#{t.lstrip('#')}" for t in tags))
        lines.append("")
    lines.append("---")
    lines.append("")

    entry = "\n".join(lines)

    is_new = not os.path.exists(VAULT_PATH)
    with open(VAULT_PATH, "a") as f:
        if is_new:
            f.write("# Inbox\n\nCaptured notes from Qubi's notes-capture (SUPER+N / research recipe).\n\n---\n\n")
        f.write(entry)

    return f"Captured to {VAULT_PATH}"


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
            send(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "protocolVersion": PROTOCOL_VERSION,
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "notes-capture", "version": "1.0.0"},
                    },
                }
            )
        elif method == "notifications/initialized":
            pass
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": req_id, "result": {"tools": [TOOL_DEF]}})
        elif method == "tools/call":
            params = req.get("params", {})
            args = params.get("arguments", {})
            if params.get("name") != "capture_note":
                send(
                    {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {"code": -32601, "message": f"Unknown tool: {params.get('name')}"},
                    }
                )
                continue
            result = capture_note(
                args.get("title", "Untitled"),
                args.get("summary", ""),
                args.get("links", []) or [],
                args.get("tags", []) or [],
            )
            send(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": [{"type": "text", "text": result}]},
                }
            )
        elif req_id is not None:
            send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown method: {method}"}})


def main_cli():
    # Direct-invocation mode for the SUPER+N Quickshell overlay -- same
    # capture_note() function the MCP tool call path uses, just reached
    # without spinning up a JSON-RPC round trip for a single one-shot call.
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--link", action="append", default=[])
    parser.add_argument("--tag", action="append", default=[])
    args = parser.parse_args()
    print(capture_note(args.title, args.summary, args.link, args.tag))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--cli":
        sys.argv.pop(1)
        main_cli()
    else:
        main()
