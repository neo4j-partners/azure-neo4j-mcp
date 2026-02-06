# Databricks Samples

Sample notebooks for integrating Neo4j MCP Server with Databricks.

## Overview

This sample demonstrates how to connect Databricks to a Neo4j graph database through the Model Context Protocol (MCP). Instead of connecting directly to Neo4j, Databricks uses a Unity Catalog HTTP connection that acts as a secure proxy to an external MCP server.

## External Hosting and the Databricks Apps Limitations

The official [Neo4j MCP server](https://github.com/neo4j/mcp) is a **Go application** that runs as a compiled binary or Docker container. This creates a fundamental incompatibility with Databricks Apps.

### Databricks Apps Runtime Constraints

Databricks Apps is a serverless platform with strict runtime limitations:

| Supported | Not Supported |
|-----------|---------------|
| Python (Streamlit, Dash, Gradio) | Go binaries |
| Node.js (React, Angular, Express) | Docker containers |
| `requirements.txt` / `package.json` dependencies | Custom runtimes |
| Pre-configured system environment | Native executables |

**Key limitations:**
- Apps run in a **managed Python/Node.js environment** - you cannot bring your own container image
- **No support for compiled languages** like Go, Rust, or C++
- App files cannot exceed **10 MB** (the Neo4j MCP server binary is larger)
- Apps can only use **existing resources** - they cannot create new infrastructure

### The Solution: External MCP Server with HTTP Proxy

Because Databricks Apps cannot run the Go-based Neo4j MCP server, we deploy it to **Azure Container Apps** and connect through Databricks' **external MCP server** integration:

```
┌─────────────────────────────────────┐      ┌──────────────────────────────────┐
│         DATABRICKS                  │      │         AZURE                    │
│                                     │      │                                  │
│   ┌─────────────────────────────┐   │      │   ┌──────────────────────────┐   │
│   │  Unity Catalog              │   │      │   │  Azure Container Apps    │   │
│   │  HTTP Connection            │───┼──────┼──▶│  Neo4j MCP Server (Go)   │   │
│   │  (MCP-enabled)              │   │      │   │  + Auth Proxy            │   │
│   └─────────────────────────────┘   │      │   └──────────────────────────┘   │
│              ▲                      │      │              │                   │
│              │                      │      │              ▼                   │
│   ┌──────────┴──────────────────┐   │      │   ┌──────────────────────────┐   │
│   │  Notebooks / Agents         │   │      │   │  Neo4j Aura              │   │
│   │  (Python, SQL)              │   │      │   │  Graph Database          │   │
│   └─────────────────────────────┘   │      │   └──────────────────────────┘   │
└─────────────────────────────────────┘      └──────────────────────────────────┘
```

This pattern is Databricks' recommended approach for integrating MCP servers that cannot run natively in Databricks Apps.

### References

- [Databricks Apps Documentation](https://docs.databricks.com/aws/en/dev-tools/databricks-apps/) - Supported frameworks and limitations
- [External MCP Servers](https://docs.databricks.com/aws/en/generative-ai/mcp/external-mcp) - How to connect to external MCP servers
- [Unity Catalog HTTP Connections](https://docs.databricks.com/aws/en/query-federation/http) - Creating HTTP connections

## How It Works

Here's the detailed request flow:

1. **MCP Server Deployment**: The Neo4j MCP server runs on Azure Container Apps, providing a JSON-RPC API that translates MCP tool calls into Cypher queries against Neo4j.

2. **Unity Catalog HTTP Connection**: Databricks creates an HTTP connection in Unity Catalog that stores the MCP server endpoint URL and authentication credentials (bearer token). This connection is marked as an "MCP connection" to enable special MCP functionality.

3. **Secure Proxy**: When notebooks or SQL queries call the MCP tools, Databricks routes requests through its internal proxy (`/api/2.0/mcp/external/{connection_name}`). This proxy adds authentication headers and forwards requests to the external MCP server.

4. **Tool Execution**: The MCP server receives JSON-RPC requests, executes the requested tool (like `get-schema` or `read-cypher`), runs the corresponding Cypher query against Neo4j, and returns results through the same path.

This architecture provides several benefits:
- **Centralized credential management** via Databricks secrets
- **Governance and auditing** through Unity Catalog
- **Network isolation** - the MCP server can be locked down to only accept requests from Databricks
- **Consistent interface** - notebooks and agents use the same MCP protocol
- **Automatic token management** - Databricks handles OAuth flows and token refresh automatically

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATABRICKS WORKSPACE                                  │
│                                                                                          │
│  ┌──────────────────┐      ┌─────────────────────────────────────────────────────────┐  │
│  │                  │      │                   UNITY CATALOG                          │  │
│  │   Notebooks /    │      │  ┌─────────────────┐    ┌────────────────────────────┐  │  │
│  │   SQL Queries    │─────▶│  │  HTTP Connection │    │  Secrets Scope             │  │  │
│  │                  │      │  │  (neo4j_mcp)     │◀───│  - mcp_endpoint            │  │  │
│  │  http_request()  │      │  │                  │    │  - mcp_api_key             │  │  │
│  │  or LangGraph    │      │  │  Is MCP: ✓       │    └────────────────────────────┘  │  │
│  │                  │      │  └────────┬────────┘                                     │  │
│  └──────────────────┘      │           │                                              │  │
│                            └───────────┼──────────────────────────────────────────────┘  │
│                                        │                                                 │
│  ┌─────────────────────────────────────┼─────────────────────────────────────────────┐  │
│  │                    DATABRICKS HTTP PROXY                                           │  │
│  │                    /api/2.0/mcp/external/{connection_name}                         │  │
│  │                                                                                    │  │
│  │    Adds Bearer Token ──▶  Forwards JSON-RPC  ──▶  Returns MCP Response            │  │
│  └─────────────────────────────────────┬─────────────────────────────────────────────┘  │
│                                        │                                                 │
└────────────────────────────────────────┼─────────────────────────────────────────────────┘
                                         │
                                         │ HTTPS (Bearer Token Auth)
                                         │ JSON-RPC 2.0 over HTTP
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              AZURE CONTAINER APPS                                        │
│                                                                                          │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           NEO4J MCP SERVER                                         │  │
│  │                                                                                    │  │
│  │   Endpoints:                    Tools:                                             │  │
│  │   - POST /mcp (JSON-RPC)        - get-schema: Returns node labels, relationships  │  │
│  │   - GET /health                 - read-cypher: Executes read-only Cypher queries  │  │
│  │                                                                                    │  │
│  │   Config: NEO4J_READ_ONLY=true (write-cypher disabled)                            │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                        │                                                 │
└────────────────────────────────────────┼─────────────────────────────────────────────────┘
                                         │
                                         │ Bolt Protocol (neo4j+s://)
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              NEO4J AURA / SELF-HOSTED                                    │
│                                                                                          │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                           GRAPH DATABASE                                           │  │
│  │                                                                                    │  │
│  │   (Nodes)──[:RELATIONSHIPS]──▶(Nodes)                                             │  │
│  │                                                                                    │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Request Flow

```
1. Notebook calls http_request() or agent invokes MCP tool
                    │
                    ▼
2. Unity Catalog resolves connection settings
                    │
                    ▼
3. Databricks proxy adds Bearer token, forwards to MCP server
                    │
                    ▼
4. MCP server parses JSON-RPC, extracts tool name and arguments
                    │
                    ▼
5. Tool handler builds Cypher query, executes against Neo4j
                    │
                    ▼
6. Results returned as JSON-RPC response through proxy to notebook
```

## Cluster Setup

Before running these notebooks, configure your Databricks cluster with the required libraries.

### 1. Create or Edit a Cluster

1. Navigate to **Compute** in the Databricks sidebar
2. Create a new cluster or edit an existing one
3. Under **Performance**, check **Machine learning** to enable ML Runtime
   - This provides pre-installed PyTorch, TensorFlow, XGBoost, and MLflow
4. Select **Databricks Runtime**: 17.3 LTS ML or later recommended
5. Enable **Single node** for development/testing (optional)

### 2. Install Required Libraries

Go to the **Libraries** tab on your cluster and install these packages from PyPI:

| Library | Version | Notes |
|---------|---------|-------|
| `databricks-agents` | `>=1.2.0` | Agent deployment framework |
| `databricks-langchain` | `>=0.11.0` | Databricks LangChain integration |
| `langgraph` | `==1.0.5` | LangGraph agent framework |
| `langchain-core` | `>=1.2.0` | LangChain core |
| `langchain-openai` | `==1.1.2` | OpenAI integration (for embeddings) |
| `mcp` | latest | Model Context Protocol |
| `databricks-mcp` | latest | Databricks MCP client |
| `pydantic` | `==2.12.5` | Data validation |
| `neo4j` | `==6.0.2` | Neo4j Python driver (optional) |
| `neo4j-graphrag` | `>=1.10.0` | Neo4j GraphRAG (optional) |

**To add a library:**
1. Click **Install new** on the Libraries tab
2. Select **PyPI** as the source
3. Enter the package name with version (e.g., `langgraph==1.0.5`)
4. Click **Install**

**Tip:** Check [PyPI](https://pypi.org/) for the latest compatible versions if you encounter dependency conflicts.

## Files

| File | Description |
|------|-------------|
| [neo4j-mcp-http-connection.ipynb](./neo4j-mcp-http-connection.ipynb) | Setup and test an HTTP connection to query Neo4j via MCP |
| [neo4j_mcp_agent.py](./neo4j_mcp_agent.py) | LangGraph agent that connects to Neo4j via external MCP HTTP connection |
| [neo4j-mcp-agent-deploy.ipynb](./neo4j-mcp-agent-deploy.ipynb) | Test, evaluate, and deploy the Neo4j MCP agent |

## Neo4j MCP HTTP Connection

The `neo4j-mcp-http-connection.ipynb` notebook demonstrates how to create a Databricks HTTP connection to the Neo4j MCP server. This enables querying Neo4j graph data directly from SQL using the `http_request` function.

### Prerequisites

1. **MCP Server Deployed**: The Neo4j MCP server must be running on Azure Container Apps
2. **Databricks Runtime**: 15.4 LTS or later, or SQL warehouse 2023.40+
3. **Unity Catalog**: Must be enabled on your workspace
4. **Secrets Configured**: Run the setup script before using the notebook

### Setup Steps

Choose one of the following options to create the HTTP connection:

#### Option 1: Manual Setup via Catalog Explorer 

Use the `MCP_ACCESS.json` file in the project root to manually configure the connection in Databricks:

1. In your Databricks workspace, navigate to **Catalog** > **External Data** > **Connections**
2. Click **Create connection**
3. Enter a connection name (e.g., `neo4j_mcp`)
4. Select **HTTP** as the connection type
5. Configure authentication:
   - **Host**: Use the `endpoint` value from `MCP_ACCESS.json`
   - **Authentication type**: Bearer Token
   - **Bearer Token**: Use the `api_key` value from `MCP_ACCESS.json`
6. Configure connection details:
   - **Base path**: Leave as `/`
   - **Is MCP connection**: Check this box to enable MCP functionality
7. Click **Create connection**

For detailed instructions, see:
- [Databricks HTTP Connections](https://docs.databricks.com/aws/en/query-federation/http)
- [External MCP Servers](https://docs.databricks.com/aws/en/generative-ai/mcp/external-mcp)

#### Option 2: Automated Setup via Notebook

**Step 1: Configure Databricks Secrets**

From your local machine (where `MCP_ACCESS.json` exists):

```bash
# Run the setup script
./scripts/setup-databricks-secrets.sh
```

This reads the MCP server credentials from `MCP_ACCESS.json` and stores them securely in Databricks secrets.

**Step 2: Import and Run the Notebook**

1. Import `neo4j-mcp-http-connection.ipynb` into your Databricks workspace
2. Attach it to a cluster running Databricks Runtime 15.4 LTS or later
3. Update the configuration cell with your secret scope name (default: `mcp-neo4j-secrets`)
4. Run all cells to create the connection and test it

**Step 3: Enable MCP Connection**

The notebook creates an HTTP connection, but you must manually enable MCP functionality:

1. In the Databricks sidebar, click **Catalog**
2. Click on the gear icon and then **Connect** -> **Connections**
3. Select the **Connections** tab
4. Click on your connection name (e.g., `neo4j_azure_beta_mcp`)
5. Click the **three-dot menu** (⋮) in the top right and select **Edit**
6. In **Authentication**, re-enter the Bearer Token (use `api_key` from `MCP_ACCESS.json`)
7. Click **Next** to proceed to **Connection details**
8. Check the **Is MCP connection** box
9. Leave **Base path** as `/`
10. Click **Update** to save

### What the Notebook Does

1. **Validates secrets** - Confirms the API key and endpoint are configured
2. **Creates HTTP connection** - Sets up a Unity Catalog connection with bearer token auth
3. **Lists MCP tools** - Verifies connectivity by listing available tools
4. **Gets Neo4j schema** - Retrieves node labels, relationships, and properties
5. **Executes read queries** - Demonstrates running Cypher queries
6. **Provides helper function** - Reusable `query_neo4j()` function for your notebooks

### Security

This integration provides **read-only access** to Neo4j. The MCP server is deployed with `NEO4J_READ_ONLY=true`, which disables the `write-cypher` tool at the server level.

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `get-schema` | Retrieve database schema |
| `read-cypher` | Execute read-only Cypher queries |

### Example Usage

After running the setup notebook, you can query Neo4j from any notebook:

```python
# Using the helper function
result = query_neo4j("MATCH (n:Person) RETURN n.name LIMIT 10")

# Or directly with SQL
spark.sql("""
    SELECT http_request(
      conn => 'neo4j_mcp',
      method => 'POST',
      path => '/',
      headers => map('Content-Type', 'application/json'),
      json => '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get-schema","arguments":{}},"id":1}'
    )
""")
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Secret not found | Run `./scripts/setup-databricks-secrets.sh` |
| Connection already exists | Drop it with `DROP CONNECTION IF EXISTS neo4j_mcp` |
| HTTP timeout | Verify MCP server is running |
| 401 Unauthorized | Re-run setup script to refresh API key |

## Neo4j MCP Agent

The `neo4j_mcp_agent.py` and `neo4j-mcp-agent-deploy.ipynb` files provide a complete LangGraph agent that connects to Neo4j via the external MCP HTTP connection.

### Architecture

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  LangGraph      │────▶│ Unity Catalog HTTP   │────▶│ Neo4j MCP Server│────▶│ Neo4j Database  │
│  Agent          │     │ Connection Proxy     │     │ (Azure)         │     │                 │
│                 │     │ /api/2.0/mcp/external│     │                 │     │                 │
└─────────────────┘     └──────────────────────┘     └─────────────────┘     └─────────────────┘
       MCP tool calls           Bearer Token              Cypher Queries
       (JSON-RPC)               from Secrets              (read-cypher tool)
```

### How It Works

1. The agent uses the Unity Catalog HTTP connection proxy URL: `{host}/api/2.0/mcp/external/{connection_name}`
2. Bearer token authentication is handled by the HTTP connection (configured via secrets)
3. The agent has access to `get-schema` and `read-cypher` MCP tools
4. Compatible with MLflow ResponsesAgent for deployment

### Usage

**Step 1: Create Unity Catalog Resources**

The agent is registered to Unity Catalog for governance. Create the catalog and schema if they don't exist:

Via Databricks UI:
1. Navigate to **Catalog** in the sidebar
2. Click **Create catalog** and enter `mcp_demo_catalog`
3. Click the catalog, then **Create schema** and enter `agents`

The model will be registered as: `mcp_demo_catalog.agents.neo4j_mcp_agent`

**Step 2: Deploy the Agent**

Import these files into your Databricks workspace:
- `neo4j_mcp_agent.py` - The agent code
- `neo4j-mcp-agent-deploy.ipynb` - The deployment notebook

Then run `neo4j-mcp-agent-deploy.ipynb`:

1. **Test the agent** - Verify it can query Neo4j
2. **Log as MLflow model** - Package for deployment
3. **Evaluate** - Assess quality with MLflow scorers
4. **Register to Unity Catalog** - Store for governance
5. **Deploy** - Create a serving endpoint

**Step 3: Verify Deployment**

Check the deployment status in **Serving endpoints**:
- Navigate to **Serving** in the sidebar (under AI/ML)
- Look for `agents_mcp_demo_catalog-...` endpoint
- Wait for **State** to show "Ready"

View the registered model in **Catalog Explorer**:
- Navigate to **Catalog** > **mcp_demo_catalog** > **agents**
- Click the **Models** tab to see `neo4j_mcp_agent`

### Agent Configuration

Edit `neo4j_mcp_agent.py` to customize:

| Setting | Description | Default |
|---------|-------------|---------|
| `LLM_ENDPOINT_NAME` | Databricks LLM endpoint | `databricks-claude-3-7-sonnet` |
| `CONNECTION_NAME` | HTTP connection name | `neo4j_azure_beta_mcp` |
| `SECRET_SCOPE` | Secrets scope name | `mcp-neo4j-secrets` |
| `system_prompt` | Agent instructions | Neo4j query assistant |

## Related Documentation

- [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) - Comprehensive architecture documentation with Mermaid diagrams
- [HTTP.md](../HTTP.md) - Full proposal and implementation details for HTTP connection
- [Databricks HTTP Connections](https://docs.databricks.com/aws/en/query-federation/http)
- [Databricks External MCP](https://docs.databricks.com/aws/en/generative-ai/mcp/external-mcp)
- [Neo4j Cypher Manual](https://neo4j.com/docs/cypher-manual/current/)
