# Neo4j MCP Server on Azure Container Apps

Deploy the official [Neo4j MCP server](https://github.com/neo4j/mcp) to Azure Container Apps, enabling AI agents to query Neo4j graph databases using the Model Context Protocol (MCP).

## Architecture

```
                                    Azure Cloud
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌─────────────┐                 ┌─────────────────────────────┐            │
│  │   AI Agent  │──── API Key ───▶│   Azure Container Apps      │            │
│  │  (Claude)   │     (Bearer)    │   Environment               │            │
│  └─────────────┘                 │  ┌───────────────────────┐  │            │
│                                  │  │  Container App        │  │            │
│                                  │  │  (Neo4j MCP Server)   │  │            │
│                                  │  │  Port 8000            │  │            │
│                                  │  │  1 Fixed Instance     │  │            │
│                                  │  └───────────────────────┘  │            │
│                                  └─────────────────────────────┘            │
│                                                   │                          │
│  ┌────────────────────────────────────────────────┼──────────────────────┐  │
│  │  Supporting Services                           │                      │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │  │
│  │  │   Azure     │  │   Azure     │  │    Log      │                   │  │
│  │  │ Container   │  │  Key Vault  │  │  Analytics  │                   │  │
│  │  │  Registry   │  │  (Secrets)  │  │ (Telemetry) │                   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                   │                          │
└───────────────────────────────────────────────────┼──────────────────────────┘
                                                    │
                                                    ▼
                                             ┌─────────────┐
                                             │  Neo4j Aura │
                                             │  Database   │
                                             └─────────────┘
```

### Components

| Component | Purpose |
|-----------|---------|
| **Container App** | Runs the Neo4j MCP server (1 fixed instance) |
| **Container Registry** | Stores Docker images with managed identity auth |
| **Key Vault** | Securely stores Neo4j credentials and API key |
| **Log Analytics** | Collects container logs and metrics |
| **Managed Identity** | Enables passwordless auth to ACR and Key Vault |

### Authentication Flow

```
AI Agent ──► API Key (Bearer Token) ──► Container App ──► Neo4j MCP Server ──► Neo4j Database
```

Clients authenticate using an API key passed in the `Authorization: Bearer <API_KEY>` header.

## Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- [Docker](https://docs.docker.com/get-docker/) with buildx support
- [Python 3.10+](https://www.python.org/downloads/) (for test client)
- Azure subscription with Contributor access
- Neo4j database (e.g., [Neo4j Aura](https://neo4j.com/cloud/aura/))

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/azure-neo4j-mcp.git
cd azure-neo4j-mcp
```

### 2. Configure Environment

**Option A: Automatic setup (recommended)**

```bash
./scripts/setup-env.sh
```

This script will:
- Detect your Azure subscription from `az` CLI
- Set default resource group and location
- Prompt for Neo4j connection details
- Generate a secure random API key

**Option B: Manual setup**

```bash
cp .env.sample .env
```

### 3. Deploy

```bash
./deploy.sh
```

This will:
1. Build the Neo4j MCP server Docker image locally
2. Push the image to Azure Container Registry
3. Deploy all Azure infrastructure via Bicep
4. Generate `MCP_ACCESS.json` with connection details

### 4. Test the Deployment

```bash
./deploy.sh test
```

### 5. Use with AI Agents

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

| Command | Description |
|---------|-------------|
| `./scripts/setup-env.sh` | Configure .env file from Azure CLI context |
| `./scripts/deploy.sh` | Full deployment (build, push, infrastructure) |
| `./scripts/deploy.sh build` | Build Docker image locally |
| `./scripts/deploy.sh push` | Push image to ACR |
| `./scripts/deploy.sh infra` | Deploy Bicep infrastructure only |
| `./scripts/deploy.sh status` | Show deployment status and outputs |
| `./scripts/deploy.sh test` | Run test client to validate |
| `./scripts/cleanup.sh` | Delete all Azure resources |

## Project Structure

```
azure-neo4j-mcp/
├── infra/
│   ├── main.bicep                # Main Bicep template
│   ├── main.bicepparam           # Deployment parameters
│   └── modules/
│       ├── managed-identity.bicep
│       ├── log-analytics.bicep
│       ├── container-registry.bicep
│       ├── key-vault.bicep
│       ├── container-environment.bicep
│       └── container-app.bicep
├── scripts/
│   ├── setup-env.sh              # Environment setup script
│   ├── deploy.sh                 # Deployment script
│   └── cleanup.sh                # Resource cleanup script
├── client/
│   ├── test_client.py            # Test client
│   └── requirements.txt
├── .env.sample                   # Environment template
├── AZURE_DEPLOY.md               # Detailed proposal/spec
└── README.md                     # This file
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

- **API Key Authentication**: All requests require a valid Bearer token
- **HTTPS Only**: TLS enforced by Container Apps ingress
- **Managed Identity**: No credentials stored in code or config files
- **Key Vault**: All secrets stored securely with RBAC access control
- **No Admin User**: Container Registry uses managed identity, not admin credentials

## Documentation

- [AZURE_DEPLOY.md](./AZURE_DEPLOY.md) - Detailed deployment proposal and implementation status
- [Neo4j MCP Server](https://github.com/neo4j/mcp) - Official Neo4j MCP server documentation
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification

## License

See [LICENSE](./LICENSE) for details.
