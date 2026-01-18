"""
Demo: MCP Write Test - Verify Read-Only Mode.

This sample tests that the MCP server correctly operates in read-only mode.
It prompts the agent to perform write operations and verifies the agent
correctly reports that write tools are not available.

The MCP server is deployed with NEO4J_READ_ONLY=true, which disables the
write-cypher tool at the server level.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from samples.shared import (
    ChatAgent,
    create_agent_client,
    get_logger,
    load_agent_config,
    print_header,
)


def load_mcp_config() -> dict[str, str | None]:
    """Load MCP server configuration from environment or MCP_ACCESS.json."""
    mcp_endpoint = os.getenv("MCP_ENDPOINT")
    api_key = os.getenv("MCP_API_KEY")

    if mcp_endpoint and api_key:
        return {"endpoint": mcp_endpoint, "api_key": api_key}

    config_path = Path(__file__).parents[4] / "MCP_ACCESS.json"
    if config_path.exists():
        with open(config_path) as f:
            config = json.load(f)
            endpoint = config.get("endpoint", "")
            mcp_path = config.get("mcp_path", "/mcp")
            return {
                "endpoint": f"{endpoint.rstrip('/')}{mcp_path}",
                "api_key": config.get("api_key"),
            }

    return {"endpoint": None, "api_key": None}


async def demo_mcp_write_test() -> None:
    """Demo: Test that the MCP server is in read-only mode.

    This demo attempts to get the agent to perform write operations
    and verifies it correctly reports that writes are not available.
    """
    from agent_framework import MCPStreamableHTTPTool
    from agent_framework.exceptions import ToolException, ToolExecutionException
    from azure.identity.aio import AzureCliCredential
    from httpx import AsyncClient

    logger = get_logger()

    print_header("Demo: MCP Write Test (Verify Read-Only Mode)")
    print("This demo tests that the MCP server operates in read-only mode.")
    print("The agent will be asked to perform write operations and should")
    print("report that write tools are not available.\n")

    agent_config = load_agent_config()
    mcp_config = load_mcp_config()

    if not agent_config.project_endpoint:
        print("Error: AZURE_AI_PROJECT_ENDPOINT not configured.")
        print("Run 'python samples/setup_env.py' to sync configuration.")
        return

    if not mcp_config["endpoint"]:
        print("Error: MCP server endpoint not configured.")
        print("Required: MCP_ENDPOINT env var or MCP_ACCESS.json")
        return

    if not mcp_config["api_key"]:
        print("Error: MCP API key not configured.")
        return

    print(f"Agent: {agent_config.name}")
    print(f"Model: {agent_config.model}")
    print(f"MCP Server: {mcp_config['endpoint']}\n")

    auth_headers = {"Authorization": f"Bearer {mcp_config['api_key']}"}

    try:
        http_client = AsyncClient(headers=auth_headers)

        mcp_tool = MCPStreamableHTTPTool(
            name="Neo4j MCP Server",
            url=mcp_config["endpoint"],
            http_client=http_client,
            load_prompts=False,
        )

        async with (
            AzureCliCredential() as credential,
            mcp_tool,
        ):
            print("Connected to MCP server!\n")

            # List available tools - should NOT include write-cypher
            print("Available tools from MCP server:")
            tool_names = []
            for func in mcp_tool.functions:
                tool_names.append(func.name)
                desc = func.description[:60] + "..." if len(func.description) > 60 else func.description
                print(f"  - {func.name}: {desc}")

            # Verify write-cypher is not available
            if "write-cypher" in tool_names:
                print("\n[WARNING] write-cypher tool is available!")
                print("The MCP server may not be deployed with NEO4J_READ_ONLY=true")
            else:
                print("\n[OK] write-cypher tool is NOT available (read-only mode confirmed)")

            print("-" * 50)

            chat_client = create_agent_client(agent_config, credential)

            try:
                agent = ChatAgent(
                    name=agent_config.name,
                    chat_client=chat_client,
                    instructions=(
                        "You are a helpful assistant with access to a Neo4j graph database. "
                        "You have MCP tools available to interact with the database. "
                        "When asked to perform operations, check what tools you have available "
                        "and use them if possible. If you cannot perform an operation, explain why."
                    ),
                    tools=mcp_tool,
                )
                print("\nAgent created with MCP tools!\n")
                print("-" * 50)

                thread = agent.get_new_thread()

                # Test queries that attempt write operations
                queries = [
                    "What tools do you have available for interacting with the database?",
                    "Create a new node with label TestNode and property name='test'. If you cannot, explain why.",
                    "Delete all nodes with label TestNode. If you cannot, explain why.",
                ]

                for i, query in enumerate(queries, 1):
                    print(f"\n[Test {i}] User: {query}\n")
                    response = await agent.run(query, thread=thread)
                    print(f"[Test {i}] Agent: {response.text}\n")
                    print("-" * 50)

                print("\n" + "=" * 50)
                print("WRITE TEST COMPLETE")
                print("=" * 50)
                print("\nIf the agent reported it cannot perform write operations,")
                print("then read-only mode is working correctly.")

            finally:
                await chat_client.close()

    except ToolException as e:
        print(f"\nConnection failed: {e}")
        if hasattr(e, 'inner_exception') and e.inner_exception:
            print(f"  Inner error: {e.inner_exception}")
        print("Check that the MCP server is deployed and the API key is correct.")
    except ToolExecutionException as e:
        print(f"\nTool execution failed: {e}")
        if hasattr(e, 'inner_exception') and e.inner_exception:
            print(f"  Inner error: {e.inner_exception}")
    except Exception as e:
        logger.error(f"Unexpected error during demo: {e}")
        print(f"\nError: {e}")
        raise
