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
| `./scripts/deploy.sh app-registration` | Deploy Entra app registration (for Neo4j Aura SSO) |
| `./scripts/deploy.sh status` | Show deployment status and outputs |
| `./scripts/deploy.sh test` | Run test client to validate |

### Cleanup

| Command | Description |
|---------|-------------|
| `./scripts/cleanup.sh` | Delete all resources (interactive, waits for completion) |
| `./scripts/cleanup.sh --force` | Delete without prompts, purge Key Vault |
| `./scripts/cleanup.sh --force --no-wait` | Fast delete without waiting (can't purge Key Vault) |
| `./scripts/cleanup.sh --app-only` | Only delete Entra App Registration |
| `./scripts/cleanup.sh --local-only` | Only remove local generated files |

**Note:** Azure Key Vault and App Registrations use soft-delete by default. The cleanup script automatically purges them (permanent deletion) so you can reuse the same names immediately.

### SSO Testing

| Command | Description |
|---------|-------------|
| `./scripts/create-user.sh` | Create Azure AD test user, generate password, update test-sso/.env |
| `./scripts/create-user.sh testuser` | Create user with specific name (appends tenant domain) |
| `cd test-sso && ./setup-env.sh` | Populate test-sso/.env from APP_REGISTRATION.json |

## Project Structure

```
azure-neo4j-mcp/
├── infra/
│   ├── main.bicep                  # Main Bicep template (orchestrates all modules)
│   ├── main.bicepparam             # Deployment parameters
│   ├── app-registration.bicep      # Standalone Entra app registration (for SSO)
│   ├── bicepconfig.json            # Bicep extension config (Microsoft Graph)
│   └── modules/
│       ├── managed-identity.bicep  # User-assigned managed identity
│       ├── log-analytics.bicep     # Log Analytics workspace
│       ├── container-registry.bicep # Azure Container Registry
│       ├── key-vault.bicep         # Azure Key Vault with secrets
│       ├── container-environment.bicep # Container Apps environment
│       ├── container-app.bicep     # Container App with sidecar
│       └── entra-app-registration.bicep # Entra app registration module
├── scripts/
│   ├── nginx/
│   │   ├── nginx.conf              # OpenResty/Lua auth proxy config
│   │   └── Dockerfile              # Auth proxy container image
│   ├── setup-env.sh                # Environment setup script
│   ├── deploy.sh                   # Deployment script
│   ├── cleanup.sh                  # Resource cleanup script
│   └── create-user.sh              # Create Azure AD test user for SSO
├── client/
│   ├── test_client.py              # Deployment validation client
│   └── requirements.txt            # Python dependencies (stdlib only)
├── test-sso/
│   ├── setup-env.sh                # Setup .env from APP_REGISTRATION.json
│   ├── test_sso.py                 # SSO authentication test script
│   ├── debug_token.py              # JWT token inspection/debugging
│   ├── pyproject.toml              # Python dependencies (msal, neo4j)
│   └── .env.sample                 # SSO test configuration template
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

## Neo4j Aura SSO 

If you're using Neo4j Aura and want to enable Single Sign-On with Microsoft Entra ID, you can deploy just the app registration without the full infrastructure:

```bash
./scripts/deploy.sh app-registration
```

This creates an Azure Entra (formerly Azure AD) application registration configured for Neo4j Aura SSO with:
- Redirect URI: `https://login.neo4j.com/login/callback`
- Required scopes: `openid`, `profile`, `email`, `User.Read`

### Output

The command generates `APP_REGISTRATION.json` with everything needed for Neo4j Aura SSO.

### Post-Deployment

**Step 1: Create a client secret**

1. Open the `portal_url` from `APP_REGISTRATION.json` (direct link to your app's credentials page)
2. Click **New client secret**
3. Copy the secret **Value** (not the secret ID) immediately - it won't be shown again
4. Paste it into `APP_REGISTRATION.json` replacing `<PASTE_SECRET_VALUE_HERE>`

**Step 2: Configure Neo4j Aura**

1. Go to [Neo4j Aura Console](https://console.neo4j.io/) > Organization > Security > Single Sign On
2. Click **New configuration** and select **Microsoft Entra ID**
3. Copy the three values from `neo4j_aura_sso` in your JSON:
   - **Client ID**
   - **Client Secret** (the value you pasted)
   - **Discovery URI**
4. Choose scope (org-level, instance-level, or both)
5. Click **Create**

For more details, see the [Neo4j Aura SSO documentation](https://neo4j.com/docs/aura/security/single-sign-on/#_microsoft_entra_id_sso).

### Testing SSO Authentication

The `test-sso/` directory contains scripts to test SSO authentication against Neo4j Aura using Azure Entra ID tokens.

#### Setup

**Option A: Auto-populate from APP_REGISTRATION.json (recommended)**

```bash
cd test-sso
./setup-env.sh
```

This reads Azure Entra config from `APP_REGISTRATION.json` and creates `.env`, preserving any existing Neo4j and user settings. You'll still need to add:
- `NEO4J_URI` - Your Neo4j Aura connection string
- `AZURE_CLIENT_SECRET` - If not already in APP_REGISTRATION.json
- `AZURE_USERNAME` / `AZURE_PASSWORD` - Test user credentials

**Option B: Manual setup**

```bash
cd test-sso
cp .env.sample .env
# Edit .env with your values
```

#### Running Tests

```bash
# Install dependencies
uv sync

# Try M2M first (no user required)
uv run python test_m2m.py

# If M2M fails, use user-based auth (requires test user)
uv run python test_sso.py

# Debug JWT token claims (useful for troubleshooting)
uv run python debug_token.py
```

#### Test Scripts

| Script | Purpose |
|--------|---------|
| `setup-env.sh` | Populates `.env` from `APP_REGISTRATION.json`, preserving existing settings |
| `validate_entra_m2m.py` | **Run first** - Validates Entra M2M setup independently of Neo4j |
| `test_m2m.py` | M2M (Client Credentials) auth test against Neo4j Aura |
| `test_sso.py` | User-based auth (ROPC flow), requires test user without MFA |
| `debug_token.py` | Decodes and analyzes JWT token claims to troubleshoot SSO issues |

The scripts use [MSAL (Microsoft Authentication Library)](https://github.com/AzureAD/microsoft-authentication-library-for-python) for Azure Entra authentication and the [Neo4j Python driver](https://neo4j.com/docs/python-manual/current/) for database connectivity.

## Documentation

- [AZURE_DEPLOY_v2.md](./AZURE_DEPLOY_v2.md) - Detailed architecture and implementation documentation
- [Neo4j MCP Server](https://github.com/neo4j/mcp) - Official Neo4j MCP server repository
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/) - Azure Container Apps documentation

## License

See [LICENSE](./LICENSE) for details.
