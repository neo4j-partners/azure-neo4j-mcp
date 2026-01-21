# Bearer Token MCP Server

Deploy the Neo4j MCP server to Azure Container Apps with native bearer token authentication for SSO/OIDC integration.

## Status

**Phase 2-5 Complete** - Infrastructure templates, deployment script, and documentation created. Ready for Phase 6 (testing and validation).

See [BEARER_AUTH_V2.md](../BEARER_AUTH_V2.md) for full implementation status.

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
- **Neo4j Aura Enterprise** with SSO enabled (verify driver-level bearer auth support)

Neo4j Community Edition and standard Aura tiers do not support OIDC at the driver level.

### Identity Provider Requirements

Any OIDC-compliant identity provider:

- Microsoft Entra ID (recommended for Azure deployments)
- Okta
- Auth0
- Keycloak
- AWS Cognito
- Google (limited group claims support)

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
NEO4J_URI=neo4j+s://xxx.databases.neo4j.io
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

For self-hosted Neo4j Enterprise, add to `neo4j.conf`:

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

### Python Example

```python
import msal
import requests

# Obtain token from Azure Entra ID
app = msal.ConfidentialClientApplication(
    client_id="your-app-id",
    authority="https://login.microsoftonline.com/your-tenant-id",
    client_credential="your-client-secret"
)
result = app.acquire_token_for_client(scopes=["api://your-app-id/.default"])
token = result["access_token"]

# Call MCP server
response = requests.post(
    "https://your-mcp-server.azurecontainerapps.io/mcp",
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
```

### curl Example

```bash
# Obtain token (using Azure CLI as example)
TOKEN=$(az account get-access-token --resource api://your-app-id --query accessToken -o tsv)

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
│   └── deploy.sh               # Deployment automation
├── client/
│   ├── test_bearer_client.py   # Test client with token acquisition
│   └── requirements.txt        # Python dependencies
├── docs/
│   ├── IDENTITY_PROVIDER_SETUP.md  # IdP configuration guides
│   └── TROUBLESHOOTING.md      # Debugging guide
├── .env.sample                 # Environment template
└── README.md
```

## Quick Start

```bash
# 1. Copy environment template
cp .env.sample .env

# 2. Configure .env with your settings
#    - AZURE_SUBSCRIPTION_ID
#    - AZURE_RESOURCE_GROUP
#    - AZURE_LOCATION
#    - NEO4J_URI
#    - NEO4J_MCP_REPO

# 3. Deploy
./scripts/deploy.sh

# 4. Configure your identity provider (see docs/IDENTITY_PROVIDER_SETUP.md)

# 5. Test with bearer token
export TOKEN=$(az account get-access-token --resource api://your-app-id --query accessToken -o tsv)
python client/test_bearer_client.py
```

## Next Steps

Phase 6-7 will add:

- End-to-end testing with real identity providers
- Validation of Neo4j OIDC configurations
- Updated root documentation

## References

- [Neo4j SSO Integration](https://neo4j.com/docs/operations-manual/current/authentication-authorization/sso-integration/)
- [Azure Container Apps Authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
- [MCP Streamable HTTP Transport](https://spec.modelcontextprotocol.io/specification/2025-03-26/basic/transports/)
- [Microsoft Entra ID with Neo4j](https://neo4j.com/blog/developer/neo4j-azure-sso/)
