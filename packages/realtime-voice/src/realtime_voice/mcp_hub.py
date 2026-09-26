"""Connections to the configured MCP servers, exposed as Realtime function tools.

Each server's tools are published as `<server>__<tool>` so tools from
different servers can't collide.

Every server gets one long-lived task that owns its connection: the MCP
transports are anyio context managers whose cancel scopes must be entered and
exited by the same task. Callers use the session from their own tasks and flag
it broken on failure; the owner task then tears it down and reconnects.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
from contextlib import AsyncExitStack
from typing import Any

from mcp import ClientSession, StdioServerParameters, types
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamablehttp_client

from .config import HttpServer, McpServer, StdioServer

log = logging.getLogger(__name__)

SEPARATOR = "__"
# Realtime function names must match this.
_VALID_NAME = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_RECONNECT_DELAY_S = 5
_CALL_TIMEOUT_S = 30
_CONNECT_WAIT_S = 5


class _Connection:
    def __init__(self, config: McpServer) -> None:
        self.config = config
        self.session: ClientSession | None = None
        self.tools: list[types.Tool] = []
        self._ready = asyncio.Event()
        self._broken = asyncio.Event()

    async def run(self) -> None:
        while True:
            try:
                async with AsyncExitStack() as stack:
                    self.session = await self._open(stack)
                    self._ready.set()
                    await self._broken.wait()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                log.error("mcp %s: connection failed: %r", self.config.name, e)
            finally:
                self._ready.clear()
                self._broken.clear()
                self.session = None
            await asyncio.sleep(_RECONNECT_DELAY_S)

    async def _open(self, stack: AsyncExitStack) -> ClientSession:
        match self.config.transport:
            case HttpServer(url=url, headers=headers):
                read, write, _ = await stack.enter_async_context(streamablehttp_client(url, headers=headers))
            case StdioServer(command=command, args=args, env=env):
                params = StdioServerParameters(command=command, args=list(args), env=env)
                read, write = await stack.enter_async_context(stdio_client(params))
        session = await stack.enter_async_context(ClientSession(read, write))
        await session.initialize()
        offered = (await session.list_tools()).tools
        allow = self.config.allow_tools
        self.tools = [t for t in offered if allow is None or t.name in allow]
        log.info("mcp %s: connected, %d of %d tools enabled", self.config.name, len(self.tools), len(offered))
        return session

    async def wait_ready(self, timeout: float) -> ClientSession | None:
        try:
            await asyncio.wait_for(self._ready.wait(), timeout)
        except TimeoutError:
            return None
        return self.session

    def mark_broken(self) -> None:
        self._broken.set()


class McpHub:
    def __init__(self, servers: list[McpServer]) -> None:
        for server in servers:
            if SEPARATOR in server.name or not _VALID_NAME.match(server.name):
                raise ValueError(f"MCP server name {server.name!r} must match {_VALID_NAME.pattern} without {SEPARATOR!r}")
        self._connections = {s.name: _Connection(s) for s in servers}
        self._tasks: list[asyncio.Task[None]] = []

    async def start(self) -> None:
        self._tasks = [asyncio.create_task(c.run(), name=f"mcp-{n}") for n, c in self._connections.items()]
        # Give servers a moment so the first conversation has their tools; one
        # that is down keeps retrying in the background.
        await asyncio.gather(*(c.wait_ready(_CONNECT_WAIT_S) for c in self._connections.values()))

    async def close(self) -> None:
        for task in self._tasks:
            task.cancel()
        await asyncio.gather(*self._tasks, return_exceptions=True)

    def realtime_tools(self) -> list[dict[str, Any]]:
        tools = []
        for conn in self._connections.values():
            if conn.session is None:
                continue
            for tool in conn.tools:
                name = f"{conn.config.name}{SEPARATOR}{tool.name}"
                if not _VALID_NAME.match(name):
                    log.warning("mcp %s: skipping tool %r, name not allowed by Realtime", conn.config.name, tool.name)
                    continue
                tools.append(
                    {
                        "type": "function",
                        "name": name,
                        "description": tool.description or "",
                        "parameters": tool.inputSchema,
                    }
                )
        return tools

    async def call(self, qualified_name: str, arguments_json: str) -> str:
        """Run a tool; always returns text for the model, errors included."""
        server, sep, tool = qualified_name.partition(SEPARATOR)
        conn = self._connections.get(server)
        if not sep or conn is None:
            return json.dumps({"error": f"unknown tool {qualified_name}"})
        try:
            arguments = json.loads(arguments_json) if arguments_json else {}
        except json.JSONDecodeError as e:
            return json.dumps({"error": f"arguments are not valid JSON: {e}"})

        session = await conn.wait_ready(_CONNECT_WAIT_S)
        if session is None:
            return json.dumps({"error": f"MCP server {server} is unavailable"})
        try:
            result = await asyncio.wait_for(session.call_tool(tool, arguments), _CALL_TIMEOUT_S)
        except Exception as e:
            log.warning("mcp %s: %s failed: %r", server, tool, e)
            conn.mark_broken()
            return json.dumps({"error": f"{qualified_name} failed: {e!r}"})
        return _result_text(result)


def _result_text(result: types.CallToolResult) -> str:
    parts = []
    for block in result.content:
        if isinstance(block, types.TextContent):
            parts.append(block.text)
        else:
            parts.append(f"[{block.type} content omitted]")
    if result.structuredContent is not None and not parts:
        parts.append(json.dumps(result.structuredContent))
    text = "\n".join(parts)
    return json.dumps({"error": text}) if result.isError else text
