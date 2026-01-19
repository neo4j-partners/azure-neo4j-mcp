# Neo4j MCP Server on Azure Container Apps

## Overview

This project deploys the official [Neo4j MCP server](https://github.com/neo4j/mcp) to Azure Container Apps, allowing AI agents to query Neo4j graph databases through the Model Context Protocol (MCP).

### What is MCP?

The Model Context Protocol is an open standard that lets AI assistants like Claude, ChatGPT, and custom agents connect to external data sources and tools. Instead of embedding database logic directly into your AI application, MCP provides a clean interface where the AI can discover available tools and call them as needed.

### What does this deployment provide?

This deployment creates a secure, production-ready MCP server in Azure that:

- Connects to your Neo4j database (such as Neo4j Aura or a self-hosted instance)
- Exposes read-only tools for schema discovery and Cypher query execution
- Protects access with API key authentication and rate limiting
- Runs as a serverless container with automatic scaling and built-in monitoring

### Why Azure Container Apps?

Azure Container Apps provides a fully managed environment for running containers without managing infrastructure. This deployment uses Container Apps because it offers HTTPS by default, integrates with Azure Key Vault for secrets, and scales to zero when not in use to minimize costs.

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
│    │  │  │  Port 8080          │         │    Port 8000 (localhost)     │  │  │   │
│    │  │  │  - API Key Validate │         │    - MCP Protocol Handler    │  │  │   │
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

### How it works

When an AI agent needs to query your Neo4j database, it sends a request to the MCP server endpoint with an API key. The request first passes through an authentication proxy that validates the API key and applies rate limiting. If the key is valid, the proxy forwards the request to the MCP server running alongside it. The MCP server then translates the request into a Cypher query, executes it against your Neo4j database, and returns the results back to the agent.

The server runs in read-only mode by default, meaning agents can explore the database schema and run queries, but cannot modify data. This is a safety measure to prevent accidental changes from AI-generated queries.

### Container Architecture

The Container App runs two containers as sidecars:

| Container | Port | Purpose |
|-----------|------|---------|
| **Auth Proxy (Nginx)** | 8080 (external) | Validates API keys, applies rate limiting, adds security headers, proxies to MCP server |
| **MCP Server** | 8000 (localhost) | Handles MCP protocol requests, executes Cypher queries against Neo4j using startup credentials |

### Supporting Services

| Service | Purpose |
|---------|---------|
| **Container Registry** | Stores Docker images with managed identity authentication |
| **Key Vault** | Securely stores Neo4j credentials and MCP API key |
| **Log Analytics** | Collects container logs and metrics for monitoring |
| **Managed Identity** | Enables passwordless authentication to ACR and Key Vault |

### Authentication Flow

The deployment uses a two-layer authentication approach:

1. **Client to MCP Server**: AI agents authenticate using an API key sent in the request header. The authentication proxy validates this key before allowing the request through.

2. **MCP Server to Neo4j**: The MCP server connects to Neo4j using credentials stored securely in Azure Key Vault. These credentials are loaded when the container starts, not passed with each request.

This separation means you can rotate the MCP API key independently of your Neo4j credentials, and the Neo4j credentials are never exposed to client applications.

## Databricks Integration

This repository includes samples for using the MCP server with Databricks, enabling AI agents and SQL queries to access Neo4j graph data.

### Why Azure Container Apps Instead of Databricks Apps?

The Neo4j MCP server is written in **Go** and runs as a **Docker container**. Databricks Apps only supports:

- **Python** frameworks (Streamlit, Dash, Gradio)
- **Node.js** frameworks (React, Angular, Express)

Databricks Apps does not support:
- Custom Docker containers
- Go binaries or other compiled languages
- Native executables or custom runtimes

Because of these limitations, the Neo4j MCP server must be hosted externally. Azure Container Apps provides a fully managed environment for running the Go-based MCP server with HTTPS, auto-scaling, and Key Vault integration.

Databricks then connects to this external MCP server through a **Unity Catalog HTTP connection**, which acts as a secure proxy. This architecture provides:

- **Centralized credential management** - Bearer tokens stored in Databricks secrets
- **Governance and auditing** - All access controlled through Unity Catalog
- **Unified interface** - External servers behave identically to Databricks-managed MCP servers
- **Automatic token management** - Databricks handles OAuth flows and token refresh

For implementation details, see [databrick_samples/README.md](./databrick_samples/README.md) and [Databricks External MCP documentation](https://docs.databricks.com/aws/en/generative-ai/mcp/external-mcp).

### What's Included

| Resource | Description |
|----------|-------------|
| `scripts/setup_databricks_secrets.sh` | Stores MCP credentials in Databricks secrets from `MCP_ACCESS.json` |
| `databrick_samples/neo4j-mcp-http-connection.ipynb` | Creates a Unity Catalog HTTP connection to the MCP server |
| `databrick_samples/neo4j_mcp_agent.py` | LangGraph agent that queries Neo4j via the HTTP connection |
| `databrick_samples/neo4j-mcp-agent-deploy.ipynb` | Tests, evaluates, and deploys the agent to a serving endpoint |

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

- **Environment variable authentication**: When running in HTTP streaming mode, the server uses `NEO4J_USERNAME` and `NEO4J_PASSWORD` environment variables to connect to Neo4j at startup. This enables fail-fast behavior where credential issues are detected immediately rather than on first request.
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
  "api_key": "<your-api-key>"
}
```

**Example Request:**

```bash
curl -X POST https://your-endpoint.azurecontainerapps.io/mcp/v1/tools/call \
  -H "Authorization: Bearer <MCP_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"name": "get-schema", "arguments": {}}'
```


### 7. Databricks Setup

After deploying the MCP server:

```bash
# Store MCP credentials in Databricks secrets
./scripts/setup_databricks_secrets.sh
```

Then import the notebooks into Databricks and follow the instructions in [databrick_samples/README.md](./databrick_samples/README.md).


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
| `list-gds-procedures` | List Graph Data Science procedures (if GDS installed) |

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

### Architecture
- [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) - Comprehensive architecture documentation with Mermaid diagrams covering the Neo4j MCP server, Azure deployment, security model, and Databricks extension

### Guides & Samples
- [samples/README.md](./samples/README.md) - Sample agent implementations
- [databrick_samples/README.md](./databrick_samples/README.md) - Databricks integration notebooks (HTTP connections, LangGraph agents)
- [HTTP.md](./HTTP.md) - Databricks HTTP connection proposal and implementation details
- [AZURE_DEPLOY_v2.md](./AZURE_DEPLOY_v2.md) - Detailed implementation documentation

### External Resources
- [Neo4j MCP Server](https://github.com/neo4j/mcp) - Official Neo4j MCP server repository
- [Neo4j Partners MCP Fork](https://github.com/neo4j-partners/mcp/tree/feat/http-env-credentials) - Fork with HTTP streaming environment variable support
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/) - Azure Container Apps documentation

## License

See [LICENSE](./LICENSE) for details.
