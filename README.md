# Neo4j MCP Server on Azure Container Apps

Deploy the official [Neo4j MCP server](https://github.com/neo4j/mcp) to Azure Container Apps, enabling AI agents to query Neo4j graph databases using the Model Context Protocol (MCP).

## Architecture

```
                                        Azure Cloud
┌────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                    │
│    ┌─────────────┐                                                                 │
│    │   AI Agent  │                                                                 │
│    │  (Claude)   │                                                                 │
│    └──────┬──────┘                                                                 │
│           │ API Key (Bearer)                                                       │
│           ▼                                                                        │
│    ┌──────────────────────────────────────────────────────────────────────────┐   │
│    │                    Azure Container Apps Environment                       │   │
│    │  ┌────────────────────────────────────────────────────────────────────┐  │   │
│    │  │                      Container App (1 replica)                      │  │   │
│    │  │  ┌─────────────────────┐         ┌──────────────────────────────┐  │  │   │
│    │  │  │  Auth Proxy (Nginx) │ ──────► │    Neo4j MCP Server          │  │  │   │
│    │  │  │  Port 8080          │ Basic   │    Port 8000 (localhost)     │  │  │   │
│    │  │  │  - API Key Validate │  Auth   │    - MCP Protocol Handler    │  │  │   │
│    │  │  │  - Rate Limiting    │         │    - Cypher Query Execution  │  │  │   │
│    │  │  │  - Security Headers │         │    - Schema Discovery        │  │  │   │
│    │  │  └─────────────────────┘         └──────────────────────────────┘  │  │   │
│    │  └────────────────────────────────────────────────────────────────────┘  │   │
│    └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
│    ┌──────────────────────────────────────────────────────────────────────────┐   │
│    │                         Supporting Services                               │   │
│    │                                                                           │   │
│    │    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────┐  │   │
│    │    │  Container  │    │  Key Vault  │    │    Log      │    │ Managed │  │   │
│    │    │  Registry   │    │  (Secrets)  │    │  Analytics  │    │Identity │  │   │
│    │    │  (Images)   │    │             │    │ (Telemetry) │    │         │  │   │
│    │    └─────────────┘    └─────────────┘    └─────────────┘    └─────────┘  │   │
│    └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                    │
└────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
                                   ┌─────────────┐
                                   │  Neo4j Aura │
                                   │  Database   │
                                   └─────────────┘
```

### Container Architecture

The Container App runs two containers as sidecars:

| Container | Port | Purpose |
|-----------|------|---------|
| **Auth Proxy (Nginx)** | 8080 (external) | Validates API keys, applies rate limiting, adds security headers, proxies to MCP server with Basic Auth |
| **MCP Server** | 8000 (localhost) | Handles MCP protocol requests, executes Cypher queries against Neo4j |

### Supporting Services

| Service | Purpose |
|---------|---------|
| **Container Registry** | Stores Docker images with managed identity authentication |
| **Key Vault** | Securely stores Neo4j credentials and MCP API key |
| **Log Analytics** | Collects container logs and metrics for monitoring |
| **Managed Identity** | Enables passwordless authentication to ACR and Key Vault |

### Authentication Flow

```
┌──────────┐      API Key       ┌────────────┐     Basic Auth     ┌────────────┐     Cypher      ┌───────────┐
│ AI Agent │ ─────────────────► │ Auth Proxy │ ─────────────────► │ MCP Server │ ──────────────► │  Neo4j    │
│          │   Bearer Token     │  (Nginx)   │  (injected from    │            │   bolt+s://     │  Database │
└──────────┘                    │            │   Key Vault)       │            │                 └───────────┘
                                └────────────┘                    └────────────┘
```

1. Client sends request with `Authorization: Bearer <API_KEY>` or `X-API-Key: <API_KEY>`
2. Auth proxy validates the API key against Key Vault secret
3. If valid, proxy injects Basic Auth credentials and forwards to MCP server
4. MCP server processes the request and queries Neo4j
5. Response flows back through the proxy to the client

## Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- [Docker](https://docs.docker.com/get-docker/) with buildx support
- [Python 3.10+](https://www.python.org/downloads/) (for test client)
- Azure subscription with Contributor access
- Neo4j database (e.g., [Neo4j Aura](https://neo4j.com/cloud/aura/))

### 1. Clone the Repositories

```bash
# Clone this deployment project
git clone https://github.com/your-org/azure-neo4j-mcp.git
cd azure-neo4j-mcp

# Clone the forked Neo4j MCP server with HTTP streaming environment variable support
git clone -b feat/http-env-credentials https://github.com/neo4j-partners/mcp.git ../mcp
```

**Why the fork?** The [neo4j-partners/mcp](https://github.com/neo4j-partners/mcp) fork on the `feat/http-env-credentials` branch adds features required for Azure Container Apps deployment:

- **Environment variable authentication fallback**: When running in HTTP streaming mode, the server can use `NEO4J_USERNAME` and `NEO4J_PASSWORD` environment variables as fallback credentials when Basic Auth headers are not provided. This enables the sidecar architecture where the auth proxy injects credentials.
- **Relaxed auth for protocol methods**: MCP handshake methods (`initialize`, `tools/list`) no longer require authentication, enabling platform health checks and capability discovery without credentials.

### 2. Configure Environment

**Automatic setup**

```bash
./scripts/setup-env.sh
```

This script will:
- Detect your Azure subscription from `az` CLI
- Set default resource group and location
- Prompt for Neo4j connection details
- Generate a secure random API key

### 3. Deploy

```bash
./scripts/deploy.sh
```

This will:
1. Deploy foundation infrastructure (ACR, Key Vault, Log Analytics)
2. Build the Neo4j MCP server and auth proxy Docker images locally
3. Push images to Azure Container Registry
4. Deploy Container App with both containers
5. Generate `MCP_ACCESS.json` with connection details

### 4. Test the Deployment

```bash
./scripts/deploy.sh test
```

### 5. Use with AI Agents

See the [samples/](./samples/) directory for complete agent implementations (samples have their own Azure AI Foundry infrastructure, separate from the MCP server):

- **langgraph-mcp-agent** - LangGraph ReAct agent that connects to the MCP server using `langchain-mcp-adapters`. Uses Azure OpenAI (GPT-4o) with Azure CLI authentication. Simple CLI interface for interactive queries.
- **sample-maf-agent** - Microsoft Agent Framework (MAF) samples using the [`agent-framework-neo4j`](https://github.com/neo4j-partners/neo4j-maf-provider) provider and [Neo4j context provider](https://github.com/neo4j-partners/neo4j-maf-provider). Creates a persistent `api-arches-agent` in Azure AI Foundry with support for fulltext, vector, and graph-enriched search strategies.

### 6. Manual Access (Optional)

After deployment, `MCP_ACCESS.json` contains everything needed to connect:

```json
{
  "endpoint": "https://neo4j-mcp-server.azurecontainerapps.io",
  "api_key": "<your-api-key>",
  "tools": ["get-schema", "read-cypher", "write-cypher"]
}
```

**Example Request:**

```bash
curl -X POST https://your-endpoint.azurecontainerapps.io/mcp/v1/tools/call \
  -H "Authorization: Bearer <MCP_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name": "get-schema", "arguments": {}}'
```

## Commands

### Deployment

| Command | Description |
|---------|-------------|
| `./scripts/setup-env.sh` | Configure .env file from Azure CLI context |
| `./scripts/deploy.sh` | Full deployment (infra + build + push + deploy) |
| `./scripts/deploy.sh redeploy` | Rebuild and redeploy containers (build + push + update app) |
| `./scripts/deploy.sh infra` | Deploy Bicep infrastructure only |
| `./scripts/deploy.sh status` | Show deployment status and outputs |
| `./scripts/deploy.sh test` | Run test client to validate |

### Cleanup

| Command | Description |
|---------|-------------|
| `./scripts/cleanup.sh` | Delete all resources (interactive, waits for completion) |
| `./scripts/cleanup.sh --force` | Delete without prompts, purge Key Vault |
| `./scripts/cleanup.sh --force --no-wait` | Fast delete without waiting (can't purge Key Vault) |
| `./scripts/cleanup.sh --local-only` | Only remove local generated files |

**Note:** Azure Key Vault uses soft-delete by default. The cleanup script automatically purges it (permanent deletion) so you can reuse the same name immediately.

### Testing

| Command | Description |
|---------|-------------|
| `./scripts/test-neo4j-connection.sh` | Test Neo4j connectivity using cypher-shell |

### Diagnostics

| Command | Description |
|---------|-------------|
| `./scripts/logs.sh` | Show last 100 MCP server logs |
| `./scripts/logs.sh <n>` | Show last n logs (e.g., `./scripts/logs.sh 50`) |

## Project Structure

```
azure-neo4j-mcp/
├── infra/
│   ├── main.bicep                  # Main Bicep template (orchestrates all modules)
│   ├── main.bicepparam             # Deployment parameters
│   ├── bicepconfig.json            # Bicep extension config (Microsoft Graph)
│   └── modules/
│       ├── managed-identity.bicep  # User-assigned managed identity
│       ├── log-analytics.bicep     # Log Analytics workspace
│       ├── container-registry.bicep # Azure Container Registry
│       ├── key-vault.bicep         # Azure Key Vault with secrets
│       ├── container-environment.bicep # Container Apps environment
│       └── container-app.bicep     # Container App with sidecar
├── scripts/
│   ├── nginx/
│   │   ├── nginx.conf              # OpenResty/Lua auth proxy config
│   │   └── Dockerfile              # Auth proxy container image
│   ├── setup-env.sh                # Environment setup script
│   ├── deploy.sh                   # Deployment script
│   ├── cleanup.sh                  # Resource cleanup script
│   └── logs.sh                     # View MCP server logs
├── client/
│   ├── test_client.py              # Deployment validation client
│   └── requirements.txt            # Python dependencies (stdlib only)
├── samples/
│   ├── langgraph-mcp-agent/        # LangGraph ReAct agent with langchain-mcp-adapters
│   └── sample-maf-agent/           # MAF agent with neo4j-maf-provider (creates api-arches-agent)
├── .env.sample                     # Environment template
├── AZURE_DEPLOY_v2.md              # Detailed implementation proposal
└── README.md                       # This file
```

## MCP Tools Available

| Tool | Description |
|------|-------------|
| `get-schema` | Retrieve database schema (labels, relationships, properties) |
| `read-cypher` | Execute read-only Cypher queries |
| `write-cypher` | Execute write Cypher queries (if enabled) |
| `list-gds-procedures` | List Graph Data Science procedures |

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| Container Apps (1 instance) | ~$15-30 |
| Container Registry (Basic) | $5 |
| Key Vault | ~$0.50 |
| Log Analytics | ~$2-5 |
| **Total** | **~$25-40** |

## Security

### Network Security
- **HTTPS Only**: TLS enforced by Container Apps ingress, HTTP not allowed
- **Internal MCP Server**: MCP server listens only on localhost, not directly accessible

### Authentication & Authorization
- **API Key Authentication**: All requests require `Authorization: Bearer <KEY>` or `X-API-Key` header
- **Managed Identity**: Passwordless authentication to ACR and Key Vault
- **Key Vault RBAC**: Secrets accessed via role-based access control, no access policies

### Request Protection
- **Rate Limiting**: 10 requests per second per IP address (configurable)
- **Request Size Limits**: Maximum 1MB request body to prevent abuse
- **Security Headers**: X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, Referrer-Policy

### Secret Management
- **Key Vault**: All secrets (Neo4j credentials, API key) stored in Azure Key Vault
- **No Hardcoded Secrets**: Secrets injected at runtime via Key Vault references
- **No Admin Users**: Container Registry uses managed identity, not admin credentials

## Documentation

- [samples/README.md](./samples/README.md) - Sample agent implementations
- [databrick_samples/README.md](./databrick_samples/README.md) - Databricks integration notebooks (HTTP connections, LangGraph agents)
- [HTTP.md](./HTTP.md) - Databricks HTTP connection proposal and implementation details
- [AZURE_DEPLOY_v2.md](./AZURE_DEPLOY_v2.md) - Detailed architecture and implementation documentation
- [Neo4j MCP Server](https://github.com/neo4j/mcp) - Official Neo4j MCP server repository
- [Neo4j Partners MCP Fork](https://github.com/neo4j-partners/mcp/tree/feat/http-env-credentials) - Fork with HTTP streaming environment variable support
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/) - Azure Container Apps documentation

## License

See [LICENSE](./LICENSE) for details.
