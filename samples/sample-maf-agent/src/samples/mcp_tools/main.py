"""
Demo: MCP Tools - Connect to Neo4j via MCP Server.

This sample demonstrates how to use the deployed Neo4j MCP server as a tool
source for Microsoft Agent Framework agents. Instead of connecting directly
to Neo4j, the agent calls the MCP server endpoint which handles the database
connection.

Pattern: Define MCP Tool at Agent Creation (Pattern 2)
Reference: agent-framework/python/samples/getting_started/agents/azure_ai/azure_ai_with_local_mcp.py

The MCP server provides three tools:
- get-schema: Retrieve the database schema
- read-cypher: Execute read-only Cypher queries
- write-cypher: Execute write Cypher queries (restricted in this sample)
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
    """Load MCP server configuration from environment or MCP_ACCESS.json.

    Configuration priority:
    1. Environment variables (MCP_ENDPOINT, MCP_API_KEY) - set by samples/setup_env.py
    2. MCP_ACCESS.json file (created by scripts/deploy.sh)

    Returns:
        Dictionary with 'endpoint' and 'api_key' keys.
    """
    # Try environment variables first (preferred - set by samples/setup_env.py)
    mcp_endpoint = os.getenv("MCP_ENDPOINT")
    api_key = os.getenv("MCP_API_KEY")

    if mcp_endpoint and api_key:
        return {"endpoint": mcp_endpoint, "api_key": api_key}

    # Fall back to MCP_ACCESS.json (created by scripts/deploy.sh)
    # Path: project_root/MCP_ACCESS.json (4 levels up from this file)
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


async def demo_mcp_tools() -> None:
    """Demo: Query Neo4j through MCP server tools.

    This demo uses Pattern 2 (Define MCP Tool at Agent Creation) where the
    MCPStreamableHTTPTool is passed directly to ChatAgent, making it
    a permanent part of the agent's definition.
    """
    # Lazy imports to avoid circular dependencies and speed up CLI startup
    from agent_framework import MCPStreamableHTTPTool
    from agent_framework.exceptions import ToolException, ToolExecutionException
    from azure.identity.aio import AzureCliCredential
    from httpx import AsyncClient

    logger = get_logger()

    print_header("Demo: MCP Tools (Neo4j via MCP Server)")
    print("This demo shows how to use the deployed Neo4j MCP server")
    print("as a tool source for the agent, following Pattern 2:")
    print("Define MCP Tool at Agent Creation.\n")

    # BEST PRACTICE: Use factory function to load config from environment
    # Reference: Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/cli.py
    agent_config = load_agent_config()
    mcp_config = load_mcp_config()

    # Validate Azure AI configuration
    if not agent_config.project_endpoint:
        print("Error: AZURE_AI_PROJECT_ENDPOINT not configured.")
        print("Run 'python samples/setup_env.py' to sync configuration.")
        return

    # Validate MCP server configuration
    if not mcp_config["endpoint"]:
        print("Error: MCP server endpoint not configured.")
        print("Required: MCP_ENDPOINT env var or MCP_ACCESS.json")
        print("Run './scripts/deploy.sh' to deploy the MCP server first.")
        return

    if not mcp_config["api_key"]:
        print("Error: MCP API key not configured.")
        print("Required: MCP_API_KEY env var or MCP_ACCESS.json")
        return

    print(f"Agent: {agent_config.name}")
    print(f"Model: {agent_config.model}")
    print(f"MCP Server: {mcp_config['endpoint']}\n")

    # Create HTTP client with Bearer token authentication
    # Reference: MCP_ACCESS.json specifies Authorization header with Bearer prefix
    # See: agent-framework/python/samples/getting_started/mcp/mcp_api_key_auth.py
    auth_headers = {"Authorization": f"Bearer {mcp_config['api_key']}"}

    try:
        # BEST PRACTICE: Grouped Async Context Managers
        # Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/tracer_aspire/simple.py
        #
        # Using `async with (resource1, resource2, ...):` provides several benefits:
        # 1. Automatic cleanup: Resources are properly closed even if exceptions occur
        # 2. No manual finally blocks: Eliminates error-prone cleanup code
        # 3. No asyncio.sleep() workarounds: Context managers handle async cleanup timing
        # 4. Clear resource lifetime: Easy to see which resources are in scope
        # 5. Proper ordering: Resources are released in reverse order of acquisition
        #
        # Note: AsyncClient must be opened first as MCPStreamableHTTPTool uses it.
        # We nest the context managers to ensure proper resource ordering.
        async with AsyncClient(headers=auth_headers) as http_client:
            # Create MCP tool with authentication and tool filtering
            # allowed_tools restricts to read-only operations for safety
            mcp_tool = MCPStreamableHTTPTool(
                name="Neo4j MCP Server",
                url=mcp_config["endpoint"],
                http_client=http_client,
                allowed_tools=["get-schema", "read-cypher"],  # Read-only for safety
            )

            # Nested grouped context managers for credential and MCP tool
            async with (
                AzureCliCredential() as credential,
                mcp_tool,
            ):
                print("Connected to MCP server!\n")

                # List discovered tools using the .functions property
                # Reference: agent-framework/_mcp.py lines 372-377
                print("Available tools from MCP server:")
                for func in mcp_tool.functions:
                    desc = func.description[:60] + "..." if len(func.description) > 60 else func.description
                    print(f"  - {func.name}: {desc}")
                print("-" * 50)

                # Create agent client and ChatAgent with MCP tools
                chat_client = create_agent_client(agent_config, credential)

                try:
                    agent = ChatAgent(
                        name=agent_config.name,
                        chat_client=chat_client,
                        instructions=(
                            "You are a helpful assistant that answers questions about data "
                            "stored in a Neo4j graph database. You have access to MCP tools that "
                            "let you:\n"
                            "- get-schema: Retrieve the database schema to understand what data exists\n"
                            "- read-cypher: Execute read-only Cypher queries to answer questions\n\n"
                            "Always start by getting the schema to understand the data model, "
                            "then formulate Cypher queries to answer user questions. "
                            "When writing Cypher queries, use best practices:\n"
                            "- Use parameterized queries when possible\n"
                            "- Limit results appropriately\n"
                            "- Use OPTIONAL MATCH for relationships that may not exist"
                        ),
                        tools=mcp_tool,  # Pattern 2: Tool defined at agent creation
                    )
                    print("\nAgent created with MCP tools!\n")
                    print("-" * 50)

                    # BEST PRACTICE: Thread Management for Multi-Turn Conversations
                    # Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/tracer_aspire/simple.py
                    #
                    # Creating an explicit thread preserves conversation history, allowing
                    # the agent to remember previous queries and build coherent responses.
                    # Without a thread, each query is treated as an independent conversation.
                    thread = agent.get_new_thread()

                    # Demo queries that work with any Neo4j database
                    queries = [
                        "What is the schema of this database?",
                        "How many nodes are in the database?",
                        "What are the most common relationship types?",
                    ]

                    for i, query in enumerate(queries, 1):
                        print(f"\n[Query {i}] User: {query}\n")

                        # Pass the thread to maintain conversation context across queries
                        response = await agent.run(query, thread=thread)
                        print(f"[Query {i}] Agent: {response.text}\n")
                        print("-" * 50)

                    print(
                        "\nDemo complete! The agent used MCP tools to query "
                        "the Neo4j database through the deployed MCP server."
                    )

                finally:
                    # IMPORTANT: Close the chat client to release aiohttp session
                    # AzureAIAgentClient doesn't support async context manager,
                    # so we must explicitly close it to avoid "Unclosed client session" warnings
                    await chat_client.close()

    except ToolException as e:
        # Connection failures, transport errors
        print(f"\nConnection failed: {e}")
        print("Check that the MCP server is deployed and the API key is correct.")
        print("Run './scripts/deploy.sh' to deploy or check MCP_ACCESS.json")
    except ToolExecutionException as e:
        # Tool execution failures, session errors
        print(f"\nTool execution failed: {e}")
        print("The MCP server is reachable but the tool call failed.")
    except Exception as e:
        logger.error(f"Unexpected error during demo: {e}")
        print(f"\nError: {e}")
        raise
