"""Client transports: unix socket (desktop) and websocket (mobile), same framing."""
import asyncio
import json
import os

import websockets
from websockets.exceptions import ConnectionClosed

from . import paths
from ._log import log


class ClientConn:
    """Wraps either a Unix-socket StreamWriter or a websocket connection
    behind the same send()/subscriptions interface."""
    _counter = 0

    def __init__(self, kind, writer):
        ClientConn._counter += 1
        self.cid = ClientConn._counter
        self.kind = kind  # "socket" | "ws"
        self.writer = writer
        self.subscriptions = set()

    async def send(self, obj):
        data = (json.dumps(obj) + "\n")
        try:
            if self.kind == "socket":
                self.writer.write(data.encode())
                await self.writer.drain()
            else:
                await self.writer.send(data)
        except (ConnectionClosed, ConnectionResetError, BrokenPipeError):
            pass


class TransportMixin:
    async def serve_socket(self):
        sock = paths.socket_path(self.cfg)
        os.makedirs(os.path.dirname(sock), exist_ok=True)
        try:
            os.unlink(sock)
        except FileNotFoundError:
            pass

        async def handle(reader, writer):
            client = ClientConn("socket", writer)
            self.clients.add(client)
            log(f"socket client connected ({len(self.clients)} total)")
            try:
                while True:
                    line = await reader.readline()
                    if not line:
                        break
                    s = line.decode(errors="replace").strip()
                    if not s:
                        continue
                    try:
                        obj = json.loads(s)
                    except json.JSONDecodeError:
                        continue
                    await self.handle_client_message(client, obj)
            except (ConnectionResetError, BrokenPipeError):
                pass
            finally:
                self.clients.discard(client)
                for sid in client.subscriptions:
                    sess = self.sessions.get(sid)
                    if sess:
                        sess.subscribers.discard(client)
                log(f"socket client disconnected ({len(self.clients)} total)")

        server = await asyncio.start_unix_server(handle, path=sock)
        log(f"listening on unix socket {sock}")
        return server

    async def serve_ws(self, host, port):
        async def handle(ws):
            client = ClientConn("ws", ws)
            self.clients.add(client)
            log(f"ws client connected ({len(self.clients)} total)")
            try:
                async for msg in ws:
                    for line in msg.splitlines():
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        await self.handle_client_message(client, obj)
            except ConnectionClosed:
                pass
            finally:
                self.clients.discard(client)
                for sid in client.subscriptions:
                    sess = self.sessions.get(sid)
                    if sess:
                        sess.subscribers.discard(client)
                log(f"ws client disconnected ({len(self.clients)} total)")

        log(f"listening on ws://{host}:{port}")
        return await websockets.serve(handle, host, port)
