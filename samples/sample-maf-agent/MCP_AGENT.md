# Proposal: MCP Server Sample Agent

## Problem Statement

The current sample-maf-agent demos connect directly to Neo4j using the `agent-framework-neo4j` context provider. This works well but does not demonstrate how to use the Neo4j MCP server that this project deploys to Azure Container Apps.

Users who deploy the MCP server need a working example showing how a Microsoft Agent Framework agent can call the MCP server's tools over HTTP. Without this, they must figure out the integration pattern themselves.

The MCP server provides three tools (`get-schema`, `read-cypher`, `write-cypher`) that any AI agent can use. Showing this integration completes the story: deploy the server, then connect an agent to it.

## Proposed Solution

Add a new sample called `mcp_tools` that creates a Microsoft Agent Framework agent using the MCP server as its tool source. Instead of connecting directly to Neo4j, the agent calls the MCP server endpoint which handles the database connection.

This sample will:

1. Connect to the MCP server using the `MCPStreamableHTTPTool` class from the agent framework
2. Automatically discover the available tools (`get-schema`, `read-cypher`, `write-cypher`)
3. Let the agent use these tools to answer questions about the Neo4j database
4. Demonstrate the HTTP-based MCP integration pattern with API key authentication

The agent will be able to:
- Retrieve the database schema to understand what data is available
- Execute Cypher queries to answer user questions
- Work with any Neo4j database connected to the MCP server

## How It Differs From Existing Samples

| Aspect | Current Samples (Context Provider) | New Sample (MCP Tools) |
|--------|-----------------------------------|------------------------|
| Connection | Direct to Neo4j database | Through MCP server HTTP endpoint |
| Tools | Context injected into prompts | Agent calls MCP tools directly |
| Query Generation | Provider generates Cypher internally | Agent generates Cypher, MCP executes |
| Configuration | Neo4j credentials in environment | MCP endpoint and API key only |
| Flexibility | Specific retrieval patterns | Any Cypher query the agent decides |

The context provider approach is better for structured RAG patterns. The MCP tools approach gives the agent more freedom to explore the database dynamically.

## Authentication

The `MCPStreamableHTTPTool` class supports authentication by accepting a pre-configured `httpx.AsyncClient` through its `http_client` parameter. This pattern is documented in the official MAF sample at:

**Reference:** `agent-framework/python/samples/getting_started/mcp/mcp_api_key_auth.py`

The authentication flow works as follows:

1. Create an `httpx.AsyncClient` with authentication headers
2. Pass that client to `MCPStreamableHTTPTool` via the `http_client` parameter
3. All HTTP requests to the MCP server automatically include those headers

The Neo4j MCP server expects an `x-api-key` header, so the configuration looks like:

```python
from httpx import AsyncClient

auth_headers = {"x-api-key": api_key}
http_client = AsyncClient(headers=auth_headers)

MCPStreamableHTTPTool(
    name="Neo4j MCP Server",
    url=mcp_endpoint,
    http_client=http_client,
)
```

Common authentication header patterns supported:
- API key header: `{"x-api-key": api_key}` or `{"X-API-Key": api_key}`
- Bearer token: `{"Authorization": f"Bearer {token}"}`
- Custom auth: `{"Authorization": f"ApiKey {key}"}`

## Requirements

### Sample Structure

1. Create a new folder at `src/samples/mcp_tools/` following the existing pattern
2. Include a main demo function that runs interactive queries
3. Use the shared utilities (AgentConfig, create_agent_client, print_header)
4. Add the demo to the CLI menu as option 5

### Configuration

1. Read MCP endpoint and API key from environment variables or MCP_ACCESS.json
2. Use Azure CLI credentials for the Azure AI agent client
3. Validate configuration before running and show clear error messages

### Agent Behavior

1. Connect to MCP server and discover available tools automatically
2. Use system instructions that explain the tools and how to use them
3. Start by fetching the schema so the agent understands the database
4. Run demo queries that show the agent using read-cypher to answer questions

### Error Handling

1. Handle MCP server connection failures gracefully
2. Show meaningful errors if the server is not deployed or API key is wrong
3. Clean up connections properly when done

### Documentation

1. Update the CLI help text with the new option
2. Add the sample to the README files list
3. Include comments explaining the MCP integration pattern

## Expected Outcomes

After this sample is implemented:

1. Users have a working example of MCP server integration with Microsoft Agent Framework
2. The sample demonstrates the full deployment story (server + agent)
3. Developers can copy the pattern for their own MCP-based agents
4. The difference between context providers and MCP tools is clear

## Files to Create or Modify

### New Files

- `src/samples/mcp_tools/__init__.py` - Package exports
- `src/samples/mcp_tools/main.py` - Demo implementation

### Modified Files

- `src/samples/shared/cli.py` - Add menu option 5 and import
- `src/samples/__init__.py` - Export new demo function
- `samples/README.md` - Document the new sample

## Dependencies

The sample requires these packages in `pyproject.toml`:

```toml
dependencies = [
    "agent-framework-azure-ai>=0.1.0",
    "agent-framework-core>=0.1.0",  # Required for MCPStreamableHTTPTool (not re-exported by azure-ai)
    "httpx>=0.27.0",  # Required for authenticated HTTP client
    "azure-identity>=1.15.0",
]
```

**Note:** While `agent-framework-azure-ai` depends on `agent-framework-core`, we list it explicitly because:
- `MCPStreamableHTTPTool` is imported from `agent_framework` (the core package)
- `AzureAIAgentClient` is imported from `agent_framework.azure_ai`
- Exception classes are imported from `agent_framework.exceptions`

## Reference Implementation Examples

The following examples from the [Microsoft Agent Framework Samples](https://github.com/Azure/Agent-Framework-Samples) demonstrate the MCP integration patterns to follow.

### Pattern 1: Pass MCP Tool at Runtime

This pattern creates the MCP tool as a context manager and passes it to the agent when invoking `run()`. Use this for session-based or temporary tool usage:

```python
from agent_framework import ChatAgent, MCPStreamableHTTPTool
from agent_framework.azure import AzureAIAgentClient
from azure.identity.aio import AzureCliCredential
from httpx import AsyncClient

# Create HTTP client with authentication headers
auth_headers = {"x-api-key": "your-api-key"}
http_client = AsyncClient(headers=auth_headers)

async with (
    AzureCliCredential() as credential,
    MCPStreamableHTTPTool(
        name="Neo4j MCP Server",
        url="https://your-mcp-server.azurecontainerapps.io/mcp",
        http_client=http_client,
    ) as mcp_server,
    ChatAgent(
        chat_client=AzureAIAgentClient(async_credential=credential),
        name="Neo4jAgent",
        instructions="You are a helpful assistant that answers questions about graph data.",
    ) as agent,
):
    query = "What is the database schema?"
    result = await agent.run(query, tools=mcp_server)
    print(f"{agent.name}: {result}")
```

### Pattern 2: Define MCP Tool at Agent Creation

This pattern passes the `MCPStreamableHTTPTool` directly into the `create_agent` method, making it a permanent part of the agent's definition:

```python
from agent_framework import MCPStreamableHTTPTool
from agent_framework.azure import AzureAIAgentClient
from azure.identity.aio import AzureCliCredential
from httpx import AsyncClient

# Create HTTP client with authentication headers
auth_headers = {"x-api-key": "your-api-key"}
http_client = AsyncClient(headers=auth_headers)

async with (
    AzureCliCredential() as credential,
    AzureAIAgentClient(async_credential=credential).create_agent(
        name="Neo4jAgent",
        instructions="You are a helpful assistant that can query a Neo4j database.",
        tools=MCPStreamableHTTPTool(
            name="Neo4j MCP Server",
            url="https://your-mcp-server.azurecontainerapps.io/mcp",
            http_client=http_client,
        ),
    ) as agent,
):
    query = "Show me all nodes connected to Customer entities"
    result = await agent.run(query)
    print(f"{agent.name}: {result}")
```

### Proposed Sample Implementation

Following the existing sample patterns in this project and incorporating all resolved design decisions:

```python
"""
Demo: MCP Tools - Connect to Neo4j via MCP Server.

Shows how to use the deployed MCP server as a tool source
instead of connecting directly to Neo4j.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from agent_framework import ChatAgent, MCPStreamableHTTPTool
from agent_framework.azure_ai import AzureAIAgentClient
from agent_framework.exceptions import ToolException, ToolExecutionException
from azure.identity.aio import AzureCliCredential
from httpx import AsyncClient

from samples.shared import AgentConfig, print_header, get_logger


def load_mcp_config() -> dict[str, str]:
    """Load MCP server configuration from environment or MCP_ACCESS.json.

    Priority:
    1. Environment variables (MCP_ENDPOINT, MCP_API_KEY)
    2. MCP_ACCESS.json file (created by deploy script)
    """
    # Try environment variables first (set by samples/setup_env.py)
    mcp_endpoint = os.getenv("MCP_ENDPOINT")
    api_key = os.getenv("MCP_API_KEY")

    if mcp_endpoint and api_key:
        return {"endpoint": mcp_endpoint, "api_key": api_key}

    # Fall back to MCP_ACCESS.json (created by deploy script)
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
    """Demo: Query Neo4j through MCP server tools."""
    logger = get_logger()

    print_header("Demo: MCP Tools (Neo4j via MCP Server)")
    print("This demo shows how to use the deployed MCP server")
    print("as a tool source for the agent.\n")

    # Load configs
    agent_config = AgentConfig()
    mcp_config = load_mcp_config()

    if not agent_config.project_endpoint:
        print("Error: AZURE_AI_PROJECT_ENDPOINT not configured.")
        print("Run 'python samples/setup_env.py' to sync configuration.")
        return

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

    # Create HTTP client with API key authentication
    # MCP_ACCESS.json specifies Bearer token format for Authorization header
    auth_headers = {"Authorization": f"Bearer {mcp_config['api_key']}"}
    http_client = AsyncClient(headers=auth_headers)

    credential = AzureCliCredential()

    try:
        async with (
            MCPStreamableHTTPTool(
                name="Neo4j MCP Server",
                url=mcp_config["endpoint"],
                http_client=http_client,
                allowed_tools=["get-schema", "read-cypher"],  # Read-only for safety
            ) as mcp_server,
            ChatAgent(
                chat_client=AzureAIAgentClient(async_credential=credential),
                name=agent_config.name,
                instructions=(
                    "You are a helpful assistant that answers questions about data "
                    "stored in a Neo4j graph database. You have access to tools that "
                    "let you:\n"
                    "- get-schema: Retrieve the database schema to understand what data exists\n"
                    "- read-cypher: Execute read-only Cypher queries to answer questions\n\n"
                    "Always start by getting the schema to understand the data model, "
                    "then formulate Cypher queries to answer user questions."
                ),
            ) as agent,
        ):
            print("Connected to MCP server!\n")

            # List discovered tools using the .functions property
            print("Available tools from MCP server:")
            for func in mcp_server.functions:
                print(f"  - {func.name}: {func.description}")
            print("-" * 50)

            # Demo queries (generic - work with any Neo4j database)
            queries = [
                "What is the schema of this database?",
                "How many nodes are in the database?",
                "What are the most common relationship types?",
            ]

            for i, query in enumerate(queries, 1):
                print(f"\n[Query {i}] User: {query}\n")
                response = await agent.run(query, tools=mcp_server)
                print(f"[Query {i}] Agent: {response.text}\n")
                print("-" * 50)

            print("\nDemo complete!")

    except ToolException as e:
        print(f"\nConnection failed: {e}")
        print("Check that the MCP server is deployed and the API key is correct.")
        print("Run './scripts/deploy.sh' to deploy or check MCP_ACCESS.json")
    except ToolExecutionException as e:
        print(f"\nTool execution failed: {e}")
        print("The MCP server is reachable but the tool call failed.")
    except Exception as e:
        logger.error(f"Unexpected error during demo: {e}")
        print(f"\nError: {e}")
        raise
    finally:
        await http_client.aclose()
        await credential.close()
```

## Integration Points

The sample connects two parts of this project:

1. **MCP Server** (deployed via `./scripts/deploy.sh`) - Provides the tools
2. **Azure AI Foundry** (deployed via `azd up` in samples/) - Hosts the agent

The MCP_ACCESS.json file created by the deploy script contains the endpoint and API key needed for the sample.

---

## Resolved Design Decisions

The following design decisions have been resolved through research of the existing codebase and the Microsoft Agent Framework.

### 1. MCP Endpoint Path

**Decision:** Use the existing `MCP_ACCESS.json` configuration pattern.

The deploy script (`scripts/deploy.sh`, lines 627-681) creates `MCP_ACCESS.json` in the project root with:
- `endpoint`: Base URL (e.g., `https://app.azurecontainerapps.io`)
- `mcp_path`: Path suffix (default `/mcp`)
- `transport`: `streamable-http`

The full endpoint URL is constructed as `{endpoint}{mcp_path}`.

**Configuration Loading Pattern** (from `samples/langgraph-mcp-agent/simple-agent.py`):
1. Primary: Load from `.env` file (`MCP_ENDPOINT`, `MCP_API_KEY`)
2. Fallback: Read `MCP_ACCESS.json` and construct endpoint

The sample should use `samples/setup_env.py` to sync `MCP_ACCESS.json` to `.env` files, following the existing pattern.

### 2. Tool Filtering/Restriction

**Decision:** Restrict to read-only tools (`get-schema`, `read-cypher`) for safety.

The `MCPStreamableHTTPTool` supports the `allowed_tools` parameter to restrict which tools are exposed:

```python
MCPStreamableHTTPTool(
    name="Neo4j MCP Server",
    url=mcp_endpoint,
    http_client=http_client,
    allowed_tools=["get-schema", "read-cypher"],  # Exclude write-cypher
)
```

**Reference:** `agent-framework/python/packages/core/agent_framework/_mcp.py`, lines 372-377

This prevents accidental data modification while still allowing full read access.

### 3. Agent Framework Package Dependencies

**Decision:** Add `agent-framework-core` explicitly to dependencies.

Research findings:
- `agent-framework-azure-ai` depends on `agent-framework-core` (pyproject.toml line 26)
- `MCPStreamableHTTPTool` is **not** re-exported by `agent-framework-azure-ai`
- The correct import is: `from agent_framework import MCPStreamableHTTPTool`

**Required imports:**
```python
from agent_framework import ChatAgent, MCPStreamableHTTPTool
from agent_framework.azure_ai import AzureAIAgentClient
from agent_framework.exceptions import ToolException, ToolExecutionException
```

**pyproject.toml update needed:**
```toml
dependencies = [
    "agent-framework-azure-ai>=0.1.0",
    "agent-framework-core>=0.1.0",  # Required for MCPStreamableHTTPTool
    "httpx>=0.27.0",  # Required for authenticated HTTP client
]
```

### 4. Error Handling for MCP Connection

**Decision:** Catch framework-specific exceptions with meaningful error messages.

The MCP implementation raises these exceptions (from `_mcp.py`):

| Exception | When Raised | Handler Action |
|-----------|-------------|----------------|
| `ToolException` | Connection failures, transport errors | Show "MCP server unreachable" message |
| `ToolExecutionException` | Tool execution failures, session errors | Show specific tool error |
| `McpError` | MCP protocol errors | Show protocol error details |
| `ClosedResourceError` | Connection closed unexpectedly | Suggest retry |

**Error handling pattern:**
```python
from agent_framework.exceptions import ToolException, ToolExecutionException

try:
    async with MCPStreamableHTTPTool(...) as mcp_server:
        # ... use tools
except ToolException as e:
    print(f"Connection failed: {e}")
    print("Check that the MCP server is deployed and the API key is correct.")
except ToolExecutionException as e:
    print(f"Tool execution failed: {e}")
```

### 5. Tool Discovery and Listing

**Decision:** Access the `.functions` property after connection to list tools.

After `MCPStreamableHTTPTool` connects (via async context manager), the discovered tools are available via the `functions` property:

```python
async with MCPStreamableHTTPTool(...) as mcp_server:
    print("Available tools from MCP server:")
    for func in mcp_server.functions:
        print(f"  - {func.name}: {func.description}")
```

**Reference:** `agent-framework/python/packages/core/agent_framework/_mcp.py`, lines 372-377

### 6. Streaming vs Non-Streaming Responses

**Decision:** Use non-streaming `run()` method, consistent with all MAF samples.

All official MCP samples use `agent.run()` for simplicity:
- `mcp_api_key_auth.py` line 55
- `azure_ai_with_local_mcp.py` lines 41, 47
- `mcp_github_pat.py` lines 70, 76

Streaming (`run_stream()`) is available but adds complexity without significant benefit for this demo.

### 7. Session/Thread Management

**Decision:** Use automatic thread management (no explicit threads needed).

Research findings:
- `ChatAgent.run()` automatically manages threads internally
- Messages are automatically added to thread history after each run
- Explicit threads are optional, only needed for multi-session persistence

For the demo, simply call `agent.run()` multiple times - history is preserved automatically within the async context.

For multi-turn conversations that should remember context:
```python
thread = agent.get_new_thread()
result1 = await agent.run(query1, thread=thread)
result2 = await agent.run(query2, thread=thread)  # Remembers query1
```

### 8. MCP_ACCESS.json Location and Format

**Decision:** Use the existing format created by `scripts/deploy.sh`.

**Location:** Project root (`/MCP_ACCESS.json`)

**Full JSON structure** (from deploy.sh lines 642-677):
```json
{
  "endpoint": "https://app.azurecontainerapps.io",
  "keyVaultName": "kv-neo4j-xxxxx",
  "mcp_path": "/mcp",
  "api_key": "your-api-key",
  "transport": "streamable-http",
  "authentication": {
    "type": "api_key",
    "header": "Authorization",
    "prefix": "Bearer",
    "alternative_header": "X-API-Key"
  },
  "tools": ["get-schema", "read-cypher", "write-cypher"]
}
```

**Configuration loading:** Use `samples/setup_env.py` to sync to `.env` files, then load from environment variables.

### 9. Demo Queries

**Decision:** Use generic queries that work with any Neo4j database.

```python
queries = [
    "What is the schema of this database?",
    "How many nodes are in the database?",
    "What are the most common relationship types?",
]
```

These queries use `get-schema` and `read-cypher` tools and work regardless of the specific data model.

---

## Next Steps

1. **Implement** - Build the sample using the resolved design decisions above
2. **Test** - Verify against a deployed MCP server
3. **Document** - Update README and add inline comments explaining the MCP pattern
