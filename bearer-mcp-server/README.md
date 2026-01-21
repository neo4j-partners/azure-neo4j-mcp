# Bearer Token MCP Server

Deploy the Neo4j MCP server to Azure Container Apps with native bearer token authentication for SSO/OIDC integration.

## Status

**Ready for Testing** - Infrastructure templates, deployment script, and documentation complete.

See [BEARER_AUTH_V2.md](../BEARER_AUTH_V2.md) for implementation details.

## Quick Start with azure-ee-template

If you've deployed Neo4j Enterprise using the [azure-ee-template](https://github.com/neo4j-partners/azure-ee-template), follow these steps:

### Prerequisites

Ensure you have:
- Deployed Neo4j Enterprise with M2M authentication enabled via azure-ee-template
- Azure CLI installed and authenticated (`az login`)
- Docker with buildx support
- The Neo4j MCP server source cloned locally

### Step 1: Copy Deployment Configuration

After deploying Neo4j with azure-ee-template, copy the deployment JSON file:

```bash
# From your azure-ee-template directory
cp azure-ee-template/.deployments/standalone-v2025.json azure-neo4j-mcp/bearer-mcp-server/neo4j-deployment.json
```

This file contains all the connection details and M2M configuration:

```json
{
  "connection": {
    "neo4j_uri": "bolt://vm0.neo4j-xxx.eastus2.cloudapp.azure.com:7687",
    "username": "neo4j",
    "password": "..."
  },
  "m2m_auth": {
    "enabled": true,
    "tenant_id": "...",
    "client_app_id": "...",
    "audience": "api://..."
  }
}
```

### Step 2: Run Setup Script

```bash
cd /Users/ryanknight/projects/azure/azure-neo4j-mcp/bearer-mcp-server

# Run the setup script
./scripts/setup-env.sh
```

The setup script will:
- Read configuration from `neo4j-deployment.json`
- Create/update `.env` with Neo4j URI and M2M settings
- Preserve existing credentials (AZURE_CLIENT_SECRET) if already set
- Auto-discover the Neo4j MCP repository path
- Prompt for any missing values

**Important**: You'll need to enter your **AZURE_CLIENT_SECRET** - this was shown during the azure-ee-template M2M setup. If you didn't save it, regenerate it in the Azure Portal.

### Step 3: Deploy

```bash
./scripts/deploy.sh
```

### Step 4: Test with Bearer Token

```bash
cd client
pip install -r requirements.txt
python test_bearer_client.py
```

### Non-Interactive Setup

For CI/CD or scripted deployments:

```bash
# Set the client secret first
export AZURE_CLIENT_SECRET="your-client-secret"

# Run non-interactive setup
./scripts/setup-env.sh --non-interactive

# Deploy
./scripts/deploy.sh
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Azure Container Apps                                                     │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Neo4j MCP Server                              │   │
│  │                    Port 8000 (external)                          │   │
│  │                                                                  │   │
│  │   Client Request                                                 │   │
│  │   Authorization: Bearer <jwt>  ──────────────────────────────>  │   │
│  │                                                                  │   │
│  │   MCP Server extracts token                                      │   │
│  │   Passes to Neo4j via BearerAuth  ───────────────────────────>  │   │
│  │                                                                  │   │
│  │   Neo4j validates token against IdP JWKS                         │   │
│  │   Query executes with user identity                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Differences from simple-mcp-server

| Aspect | simple-mcp-server | bearer-mcp-server |
|--------|-------------------|-------------------|
| **Containers** | Two (Nginx proxy + MCP server) | One (MCP server only) |
| **Authentication** | Static API key | JWT bearer tokens |
| **Neo4j Credentials** | Environment variables | Per-request bearer tokens |
| **Identity** | Shared across all callers | Per-caller identity |
| **Audit Trail** | API key used | User identity logged |
| **Requirements** | Any Neo4j | Neo4j Enterprise with OIDC |

## Prerequisites

### Azure Requirements

- Azure subscription with permissions to create resources
- Azure CLI installed and authenticated
- Docker with buildx support

### Neo4j Requirements

Bearer token authentication requires Neo4j to validate JWT tokens:

- **Neo4j Enterprise Edition** (self-hosted) with OIDC configured, OR
- **Neo4j deployed via azure-ee-template** with M2M authentication enabled

Neo4j Community Edition and standard Aura tiers do not support OIDC at the driver level.

### Identity Provider Requirements

Any OIDC-compliant identity provider:

- Microsoft Entra ID (recommended for Azure deployments)
- Okta
- Auth0
- Keycloak
- AWS Cognito

---

## Integration with azure-ee-template

The [azure-ee-template](https://github.com/neo4j-partners/azure-ee-template) provides automated Neo4j Enterprise deployment with optional M2M (Machine-to-Machine) bearer token authentication.

### How azure-ee-template M2M Works

When you run `uv run neo4j-deploy setup` in the azure-ee-template, Step 7 offers M2M configuration:

1. **Automatic Setup**: Creates Azure Entra ID app registrations
   - **API App**: Represents Neo4j as an API resource with roles (Admin, ReadWrite, ReadOnly)
   - **Client App**: For your applications to authenticate

2. **OIDC Configuration**: Injects into Neo4j's `neo4j.conf`:
   ```properties
   dbms.security.authentication_providers=oidc-m2m,native
   dbms.security.authorization_providers=oidc-m2m,native
   dbms.security.oidc.m2m.well_known_discovery_uri=https://login.microsoftonline.com/{tenant}/.well-known/openid-configuration
   dbms.security.oidc.m2m.audience={audience}
   dbms.security.oidc.m2m.authorization.group_to_role_mapping="Neo4j.Admin"=admin;"Neo4j.ReadWrite"=editor;"Neo4j.ReadOnly"=reader
   ```

### Deployment JSON File

After deploying with azure-ee-template, a JSON file is created at `.deployments/<scenario>.json` containing all configuration:

```json
{
  "scenario": "standalone-v2025",
  "connection": {
    "neo4j_uri": "bolt://vm0.neo4j-xxx.eastus2.cloudapp.azure.com:7687",
    "username": "neo4j",
    "password": "..."
  },
  "m2m_auth": {
    "enabled": true,
    "tenant_id": "...",
    "client_app_id": "...",
    "audience": "api://...",
    "token_endpoint": "https://login.microsoftonline.com/.../oauth2/v2.0/token"
  }
}
```

The `setup-env.sh` script reads this file to configure your `.env` automatically.

### Important: Save Your Client Secret

During azure-ee-template M2M setup, a client secret is displayed **once**. Save it immediately!

If you lose it, regenerate in Azure Portal:
1. Go to **App registrations**
2. Find the client app (check `client_app_id` in deployment JSON)
3. Navigate to **Certificates & secrets**
4. Create a new client secret

---

## Infrastructure Components

The Bicep templates create:

| Resource | Purpose |
|----------|---------|
| **Managed Identity** | ACR image pull authentication |
| **Log Analytics** | Container telemetry and logging |
| **Container Registry** | Docker image storage |
| **Key Vault** | Connection info storage (no credentials) |
| **Container Environment** | Container Apps hosting |
| **Container App** | Single MCP server container |

## Key Vault Contents

In bearer mode, Key Vault stores only connection information:

| Secret | Purpose |
|--------|---------|
| `neo4j-uri` | Database connection string |
| `neo4j-database` | Target database name |

**Not Stored** (authentication via bearer tokens):
- No `neo4j-username`
- No `neo4j-password`
- No `mcp-api-key`

## Environment Variables

### Required

```bash
# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_RESOURCE_GROUP=neo4j-mcp-bearer-rg
AZURE_LOCATION=eastus

# Neo4j Connection
NEO4J_URI=bolt://vm0.neo4j-xxx.eastus2.cloudapp.azure.com:7687

# Build Configuration
NEO4J_MCP_REPO=/path/to/neo4j-mcp-source
```

### Optional

```bash
NEO4J_DATABASE=neo4j              # Default: neo4j
BASE_NAME=neo4jmcp                # Resource naming prefix
ENVIRONMENT=dev                   # dev, staging, prod
NEO4J_READ_ONLY=true              # Disable write-cypher tool
CORS_ALLOWED_ORIGINS=*            # CORS configuration
```

## Authentication Flow

1. Client obtains JWT from identity provider (Entra ID, Okta, etc.)
2. Client sends MCP request with `Authorization: Bearer <token>`
3. MCP server extracts token from header
4. MCP server passes token to Neo4j via `BearerAuth`
5. Neo4j validates token against IdP JWKS endpoint
6. Query executes with caller's identity and permissions
7. Audit logs show user identity

## Neo4j OIDC Configuration

### For azure-ee-template Deployments

If you used azure-ee-template with M2M enabled, Neo4j is already configured. The OIDC provider is named `oidc-m2m`:

```properties
dbms.security.authentication_providers=oidc-m2m,native
dbms.security.authorization_providers=oidc-m2m,native
dbms.security.oidc.m2m.well_known_discovery_uri=https://login.microsoftonline.com/{tenant-id}/.well-known/openid-configuration
dbms.security.oidc.m2m.audience={audience}
dbms.security.oidc.m2m.claims.username=sub
dbms.security.oidc.m2m.claims.groups=roles
dbms.security.oidc.m2m.authorization.group_to_role_mapping="Neo4j.Admin"=admin;"Neo4j.ReadWrite"=editor;"Neo4j.ReadOnly"=reader
```

### For Manual Neo4j Enterprise Setup

Add to `neo4j.conf`:

```properties
# Enable OIDC authentication
dbms.security.authentication_providers=oidc-azure,native
dbms.security.authorization_providers=oidc-azure,native

# Azure Entra ID configuration (example)
dbms.security.oidc.azure.well_known_discovery_uri=https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration
dbms.security.oidc.azure.audience={app-id}
dbms.security.oidc.azure.claims.username=preferred_username
dbms.security.oidc.azure.claims.groups=groups

# Map IdP groups to Neo4j roles
dbms.security.oidc.azure.authorization.group_to_role_mapping=neo4j-admins=admin;neo4j-readers=reader
```

## Client Usage

### Python Example with azure-ee-template M2M

```python
from msal import ConfidentialClientApplication
import requests

# M2M configuration from azure-ee-template settings.yaml
TENANT_ID = "your-tenant-id"
CLIENT_ID = "your-client-app-id"
CLIENT_SECRET = "your-client-secret"
AUDIENCE = "api://neo4j-m2m"  # or your custom audience

# Obtain token from Azure Entra ID
app = ConfidentialClientApplication(
    client_id=CLIENT_ID,
    authority=f"https://login.microsoftonline.com/{TENANT_ID}",
    client_credential=CLIENT_SECRET
)
result = app.acquire_token_for_client(scopes=[f"{AUDIENCE}/.default"])
token = result["access_token"]

# Call MCP server
MCP_ENDPOINT = "https://your-mcp-server.azurecontainerapps.io"
response = requests.post(
    f"{MCP_ENDPOINT}/mcp",
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    },
    json={
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": "read-cypher",
            "arguments": {"query": "MATCH (n) RETURN count(n)"}
        },
        "id": 1
    }
)
print(response.json())
```

### curl Example

```bash
# Obtain token using Azure CLI
TOKEN=$(az account get-access-token \
  --resource api://neo4j-m2m \
  --query accessToken -o tsv)

# Call MCP server
curl -X POST https://your-mcp-server.azurecontainerapps.io/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "read-cypher",
      "arguments": {"query": "MATCH (n) RETURN count(n)"}
    },
    "id": 1
  }'
```

### Using the Test Client

```bash
cd client

# Set environment variables
export MCP_ENDPOINT="https://your-mcp-server.azurecontainerapps.io"
export AZURE_TENANT_ID="your-tenant-id"
export AZURE_CLIENT_ID="your-client-app-id"
export AZURE_CLIENT_SECRET="your-client-secret"

# Or set MCP_BEARER_TOKEN directly if you have a token
# export MCP_BEARER_TOKEN="eyJ..."

# Run tests
pip install -r requirements.txt
python test_bearer_client.py
```

## Security Benefits

- **No Static Secrets**: Eliminates long-lived API keys
- **Token Expiration**: JWTs expire automatically (typically 1 hour)
- **MFA Support**: Leverage identity provider MFA policies
- **Conditional Access**: Apply IdP access policies
- **User-Level Audit**: Every query attributed to a user
- **Revocation**: Disable user in IdP for immediate access removal

## Resource Comparison

| Resource | simple-mcp-server | bearer-mcp-server | Savings |
|----------|-------------------|-------------------|---------|
| **CPU** | 0.75 vCPU | 0.5 vCPU | 33% |
| **Memory** | 1.5 GiB | 1.0 GiB | 33% |
| **Containers** | 2 | 1 | 50% |
| **Key Vault Secrets** | 5 | 2 | 60% |

## Project Structure

```
bearer-mcp-server/
├── infra/
│   ├── main.bicep              # Main orchestration template
│   ├── main.bicepparam         # Parameter file
│   ├── bicepconfig.json        # Linting configuration
│   └── modules/
│       ├── container-app.bicep       # Single-container app
│       ├── container-environment.bicep
│       ├── container-registry.bicep
│       ├── key-vault.bicep           # Minimal secrets
│       ├── log-analytics.bicep
│       └── managed-identity.bicep
├── scripts/
│   ├── setup-env.sh            # Environment setup from deployment JSON
│   ├── deploy.sh               # Deployment automation
│   └── cleanup.sh              # Delete Azure resources
├── client/
│   ├── test_bearer_client.py   # Test client with token acquisition
│   └── requirements.txt        # Python dependencies
├── docs/
│   ├── IDENTITY_PROVIDER_SETUP.md  # IdP configuration guides
│   └── TROUBLESHOOTING.md      # Debugging guide
├── neo4j-deployment.json       # Copy from azure-ee-template (not in git)
├── .env.sample                 # Environment template
├── .env                        # Your configuration (not in git)
└── README.md
```

## Commands

```bash
# Setup environment from azure-ee-template deployment
cp /path/to/azure-ee-template/.deployments/standalone-v2025.json ./neo4j-deployment.json
./scripts/setup-env.sh

# Setup (non-interactive, requires AZURE_CLIENT_SECRET env var)
./scripts/setup-env.sh --non-interactive

# Full deployment
./scripts/deploy.sh

# Rebuild and redeploy container only
./scripts/deploy.sh redeploy

# Test bearer token authentication
./scripts/deploy.sh test

# Validate Bicep templates
./scripts/deploy.sh lint

# Show deployment status
./scripts/deploy.sh status

# View container logs
./scripts/deploy.sh logs 100

# Cleanup - delete all Azure resources (fast, no prompts)
./scripts/cleanup.sh

# Cleanup - interactive with confirmation
./scripts/cleanup.sh --interactive

# Cleanup - wait and purge Key Vault immediately
./scripts/cleanup.sh --wait
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

Quick checks:
1. Is Neo4j configured for OIDC? Check `neo4j.conf`
2. Is the token audience correct? Decode at [jwt.io](https://jwt.io)
3. Can Neo4j reach the IdP's JWKS endpoint?
4. Are Neo4j roles mapped correctly?

## References

- [azure-ee-template](https://github.com/neo4j-partners/azure-ee-template) - Neo4j Enterprise Azure deployment
- [Neo4j SSO Integration](https://neo4j.com/docs/operations-manual/current/authentication-authorization/sso-integration/)
- [Azure Container Apps Authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [MCP Streamable HTTP Transport](https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/transports/)
- [Microsoft Entra ID with Neo4j](https://neo4j.com/blog/developer/neo4j-azure-sso/)
