"""WebSocket -> goose acp relay bridge."""
import asyncio
from websockets.exceptions import ConnectionClosed
import websockets


HOST, PORT = "100.66.17.61", 8765


async def handler(websocket):
    print(f"[goose_bridge] client connected", flush=True)

    # 1. Spawn goose acp subprocess
    proc = await asyncio.create_subprocess_exec(
        "goose", "acp",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
    )

    # 2a. Relay subprocess stdout -> websocket
    async def relay_to_ws():
        while True:
            line = await proc.stdout.readline()
            if not line:
                break
            await websocket.send(line.decode())

    # 2b. Relay websocket -> subprocess stdin
    async def relay_from_ws():
        async for msg in websocket:
            proc.stdin.write((msg + "\n").encode())
            await proc.stdin.drain()

    to_ws = asyncio.create_task(relay_to_ws())
    from_ws = asyncio.create_task(relay_from_ws())
    try:
        # Either direction finishing (client disconnect, or the subprocess
        # exiting) must end the whole handler -- gather() would otherwise
        # wait forever for the other side, leaking the subprocess and an
        # Ollama generation slot for every connection that ever drops
        # uncleanly. Confirmed live: this leaked 24 orphaned `goose acp`
        # processes in one test session before this fix.
        done, pending = await asyncio.wait(
            [to_ws, from_ws], return_when=asyncio.FIRST_COMPLETED
        )
        for task in pending:
            task.cancel()
        for task in done:
            exc = task.exception()
            if exc is not None and not isinstance(exc, ConnectionClosed):
                raise exc
    finally:
        if proc.returncode is None:
            proc.terminate()
            try:
                await asyncio.wait_for(proc.wait(), timeout=3)
            except asyncio.TimeoutError:
                # goose acp didn't react to SIGTERM in time (e.g. blocked
                # mid-generation) -- force it rather than leak the process
                # and its Ollama slot indefinitely.
                proc.kill()
        print(f"[goose_bridge] client disconnected", flush=True)


async def main():
    async with websockets.serve(handler, HOST, PORT):
        print(f"[goose_bridge] listening on ws://{HOST}:{PORT}", flush=True)
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    asyncio.run(main())
