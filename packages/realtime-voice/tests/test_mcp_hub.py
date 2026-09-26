"""The hub against real MCP servers over stdio."""

import asyncio
import json
import os
import sys
import textwrap
from pathlib import Path

import pytest

from realtime_voice.config import McpServer, StdioServer
from realtime_voice.mcp_hub import McpHub

SERVER = textwrap.dedent(
    """
    import sys
    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP(sys.argv[1])

    @mcp.tool()
    def echo(text: str) -> str:
        "Echo the text back."
        return sys.argv[1] + ":" + text

    @mcp.tool()
    def secret() -> str:
        "Not allowlisted."
        return "nope"

    mcp.run()
    """
)


@pytest.fixture
def server_script(tmp_path: Path) -> Path:
    path = tmp_path / "server.py"
    path.write_text(SERVER)
    return path


def stdio(name: str, script: Path, allow=None) -> McpServer:
    # The MCP client passes only a minimal environment to servers; the test
    # server needs to import mcp from this interpreter's path.
    env = {"PYTHONPATH": os.pathsep.join(sys.path)}
    return McpServer(name, StdioServer(sys.executable, (str(script), name), env), allow)


def test_tools_are_namespaced_and_filtered(server_script):
    async def main():
        hub = McpHub([stdio("home", server_script), stdio("notes", server_script, frozenset({"echo"}))])
        await hub.start()
        try:
            names = sorted(t["name"] for t in hub.realtime_tools())
            assert names == ["home__echo", "home__secret", "notes__echo"]
            assert await hub.call("notes__echo", json.dumps({"text": "hi"})) == "notes:hi"
            assert await hub.call("home__echo", json.dumps({"text": "yo"})) == "home:yo"
            assert "error" in json.loads(await hub.call("nosuch__echo", "{}"))
            assert "error" in json.loads(await hub.call("home__echo", "not json"))
        finally:
            await hub.close()

    asyncio.run(main())


def test_rejects_ambiguous_server_names(server_script):
    with pytest.raises(ValueError):
        McpHub([stdio("a__b", server_script)])
