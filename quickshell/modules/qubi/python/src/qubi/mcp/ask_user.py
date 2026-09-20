#!/usr/bin/env python3
"""ask-user MCP server (stdio JSON-RPC).

Exposes one tool, ask_user(question, options, allow_free_text), that blocks
until a real human answers via the Quickshell askuser overlay (SUPER
IPC-triggered by this script, same convention every other overlay in this
repo uses). Deliberately does NOT use MCP's elicitation/create -- whether
the pinned Goose 1.47.0 advertises elicitation support and propagates it
through its ACP surface to the chat overlay was never confirmed live (see
docs/history/BLOCKERS-2026-09-19.md: the eGPU hit a dead-KFD state mid-session, which made every
live goose acp + tool-call test impossible for the rest of the night).
Blocking synchronously inside a plain tools/call response works regardless
of whether the client understands elicitation at all -- from Goose's side
this just looks like a slow tool call, which the existing permission/
timeout machinery already handles.

Handoff to the QML side is a simple file-based side channel (matching this
project's own precedent: state.json for ai-workstation, results.jsonl for
goose-bench) rather than a socket -- one shot, no daemon needed:
  1. Write the request to REQUEST_FILE.
  2. IPC-trigger the askuser overlay to show it.
  3. Poll for RESPONSE_FILE (the overlay writes it on submit).
  4. Clean up both files, return the answer as the tool result.
"""
import json
import os
import subprocess
import sys
import time
import uuid

STATE_DIR = os.path.expanduser("~/.local/share/qubi/ask-user")
POLL_INTERVAL = 0.3
TIMEOUT_SECONDS = 300  # a human may be away from the keyboard briefly

PROTOCOL_VERSION = "2024-11-05"


def _quickshell_ipc():
    """`quickshell ipc` argv addressing the shell that hosts the askuser
    overlay. $QUBI_SHELL_PATH is the config directory that shell was started
    with (`quickshell -p <path>`); unset means the default config."""
    shell_path = os.environ.get("QUBI_SHELL_PATH")
    return ["quickshell", "ipc"] + (["-p", os.path.expanduser(shell_path)] if shell_path else [])


TOOL_DEF = {
    "name": "ask_user",
    "description": (
        "Ask the human a question and block until they answer, via a real "
        "on-screen dialog (not a guess). Use when a task genuinely cannot "
        "proceed without a decision only the user can make -- not for "
        "things you can reasonably infer yourself."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "question": {"type": "string", "description": "The question to ask"},
            "options": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Multiple-choice options to present as buttons. Omit for a free-text-only question.",
            },
            "allow_free_text": {
                "type": "boolean",
                "description": "Whether to also allow a typed answer alongside/instead of the options. Defaults to true if options is empty, false otherwise.",
            },
        },
        "required": ["question"],
    },
}


def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def ask_user(question, options, allow_free_text):
    os.makedirs(STATE_DIR, exist_ok=True)
    req_id = str(uuid.uuid4())
    request_file = os.path.join(STATE_DIR, f"request-{req_id}.json")
    response_file = os.path.join(STATE_DIR, f"response-{req_id}.json")

    with open(request_file, "w") as f:
        json.dump(
            {
                "id": req_id,
                "question": question,
                "options": options,
                "allow_free_text": allow_free_text,
                "response_file": response_file,
            },
            f,
        )

    try:
        subprocess.run(
            _quickshell_ipc() + ["call", "askuser", "show", req_id],
            capture_output=True,
            timeout=5,
        )
    except Exception as e:
        return f"Could not reach the Quickshell askuser overlay ({e}) -- is Quickshell running?"

    deadline = time.time() + TIMEOUT_SECONDS
    while time.time() < deadline:
        if os.path.exists(response_file):
            try:
                with open(response_file) as f:
                    data = json.load(f)
                return data.get("answer", "(empty answer)")
            finally:
                for f in (request_file, response_file):
                    try:
                        os.remove(f)
                    except OSError:
                        pass
        time.sleep(POLL_INTERVAL)

    try:
        os.remove(request_file)
    except OSError:
        pass
    return "The user did not respond within 5 minutes. Proceed with your best judgment, or state that you're blocked on this question."


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
                        "serverInfo": {"name": "ask-user", "version": "1.0.0"},
                    },
                }
            )
        elif method == "notifications/initialized":
            pass  # no response for notifications
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": req_id, "result": {"tools": [TOOL_DEF]}})
        elif method == "tools/call":
            params = req.get("params", {})
            args = params.get("arguments", {})
            if params.get("name") != "ask_user":
                send(
                    {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {"code": -32601, "message": f"Unknown tool: {params.get('name')}"},
                    }
                )
                continue
            question = args.get("question", "")
            options = args.get("options", []) or []
            allow_free_text = args.get("allow_free_text", len(options) == 0)
            answer = ask_user(question, options, allow_free_text)
            send(
                {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": [{"type": "text", "text": answer}]},
                }
            )
        elif req_id is not None:
            send({"jsonrpc": "2.0", "id": req_id, "error": {"code": -32601, "message": f"Unknown method: {method}"}})


if __name__ == "__main__":
    main()
