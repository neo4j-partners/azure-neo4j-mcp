# Databricks Samples

Sample notebooks for integrating Neo4j MCP Server with Databricks.

## Notebooks

| Notebook | Description |
|----------|-------------|
| [neo4j-mcp-http-connection.ipynb](./neo4j-mcp-http-connection.ipynb) | Setup and test an HTTP connection to query Neo4j via MCP |
| [langgraph-mcp-tool-calling-agent.ipynb](./langgraph-mcp-tool-calling-agent.ipynb) | LangGraph agent with MCP tool calling |

## Neo4j MCP HTTP Connection

The `neo4j-mcp-http-connection.ipynb` notebook demonstrates how to create a Databricks HTTP connection to the Neo4j MCP server. This enables querying Neo4j graph data directly from SQL using the `http_request` function.

### Prerequisites

1. **MCP Server Deployed**: The Neo4j MCP server must be running on Azure Container Apps
2. **Databricks Runtime**: 15.4 LTS or later, or SQL warehouse 2023.40+
3. **Unity Catalog**: Must be enabled on your workspace
4. **Secrets Configured**: Run the setup script before using the notebook

### Setup Steps

**Step 1: Configure Databricks Secrets**

From your local machine (where `MCP_ACCESS.json` exists):

```bash
# Run the setup script
./scripts/setup_databricks_secrets.sh
```

This reads the MCP server credentials from `MCP_ACCESS.json` and stores them securely in Databricks secrets.

**Step 2: Import and Run the Notebook**

1. Import `neo4j-mcp-http-connection.ipynb` into your Databricks workspace
2. Attach it to a cluster running Databricks Runtime 15.4 LTS or later
3. Update the configuration cell with your secret scope name (default: `mcp-neo4j-secrets`)
4. Run all cells to create the connection and test it

### What the Notebook Does

1. **Validates secrets** - Confirms the API key and endpoint are configured
2. **Creates HTTP connection** - Sets up a Unity Catalog connection with bearer token auth
3. **Lists MCP tools** - Verifies connectivity by listing available tools
4. **Gets Neo4j schema** - Retrieves node labels, relationships, and properties
5. **Executes read queries** - Demonstrates running Cypher queries
6. **Provides helper function** - Reusable `query_neo4j()` function for your notebooks

### Security

This integration provides **read-only access** to Neo4j. The `write-cypher` tool is intentionally excluded to prevent accidental data modifications from analytics workflows.

### Available MCP Tools

| Tool | Description | Available |
|------|-------------|-----------|
| `get-schema` | Retrieve database schema | Yes |
| `read-cypher` | Execute read-only Cypher queries | Yes |
| `write-cypher` | Execute write Cypher queries | No (excluded) |

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
| Secret not found | Run `./scripts/setup_databricks_secrets.sh` |
| Connection already exists | Drop it with `DROP CONNECTION IF EXISTS neo4j_mcp` |
| HTTP timeout | Verify MCP server is running |
| 401 Unauthorized | Re-run setup script to refresh API key |

## LangGraph MCP Tool-Calling Agent

The `langgraph-mcp-tool-calling-agent.ipynb` notebook demonstrates how to build a LangGraph agent that connects to MCP servers hosted on Databricks. This is useful for building AI agents that can query Neo4j as part of multi-step reasoning workflows.

See the notebook for detailed instructions on:
- Connecting to Databricks MCP servers
- Building custom agent workflows
- Deploying agents to model serving endpoints

## Related Documentation

- [HTTP.md](../HTTP.md) - Full proposal and implementation details for HTTP connection
- [Databricks HTTP Connections](https://docs.databricks.com/aws/en/query-federation/http)
- [Databricks External MCP](https://docs.databricks.com/aws/en/generative-ai/mcp/external-mcp)
- [Neo4j Cypher Manual](https://neo4j.com/docs/cypher-manual/current/)
