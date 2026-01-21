# Bearer Token Authentication Deployment Proposal

This document proposes modifications to the Azure deployment of the Neo4j MCP server to optionally support bearer token authentication, eliminating the need for the Nginx authentication proxy and enabling enterprise SSO/OIDC workflows.

## Table of Contents

- [Executive Summary](#executive-summary)
- [Current Architecture](#current-architecture)
- [Proposed Architecture with Bearer Authentication](#proposed-architecture-with-bearer-authentication)
- [Why Bearer Token Authentication](#why-bearer-token-authentication)
- [Deployment Changes](#deployment-changes)
- [Infrastructure Changes](#infrastructure-changes)
- [Identity Provider Integration](#identity-provider-integration)
- [Migration Path](#migration-path)
- [Security Considerations](#security-considerations)
- [Operational Impact](#operational-impact)
- [Decision Points](#decision-points)

---

## Executive Summary

The current Azure deployment uses a two-container architecture: an Nginx authentication proxy validates a static API key before forwarding requests to the Neo4j MCP server. This proposal introduces an optional `--bearer` flag to the deployment script that removes the Nginx proxy and leverages the Neo4j MCP server's native bearer token authentication capabilities.

Bearer token authentication enables enterprise SSO/OIDC workflows where clients authenticate with an identity provider (Microsoft Entra ID, Okta, etc.) and present JWT tokens directly to the MCP server. The MCP server passes these tokens to Neo4j for validation, enabling true end-to-end identity-based access control.

**Proposed Usage:**
```bash
./scripts/deploy.sh --bearer
```

---

## Current Architecture

### Two-Container Sidecar Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Azure Container Apps                                                     │
│                                                                         │
│  ┌─────────────────────────┐      ┌─────────────────────────────────┐  │
│  │   Auth Proxy (Nginx)    │      │      Neo4j MCP Server           │  │
│  │   Port 8080 (external)  │─────>│      Port 8000 (localhost)      │  │
│  │                         │      │                                 │  │
│  │  • Validates MCP_API_KEY│      │  • Receives pre-authenticated   │  │
│  │  • Rate limiting        │      │    requests                     │  │
│  │  • Security headers     │      │  • Uses env var credentials     │  │
│  │  • Health endpoints     │      │    for Neo4j connection         │  │
│  └─────────────────────────┘      └─────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Current Authentication Flow

1. Client obtains static API key from deployment output
2. Client sends request with `Authorization: Bearer <MCP_API_KEY>` or `X-API-Key` header
3. Nginx proxy validates the static key against environment variable
4. If valid, Nginx strips the Authorization header and forwards to MCP server
5. MCP server connects to Neo4j using credentials from environment variables
6. All requests share the same Neo4j connection identity

### Current Secrets in Key Vault

| Secret | Purpose |
|--------|---------|
| `neo4j-uri` | Database connection string |
| `neo4j-username` | Static database credentials |
| `neo4j-password` | Static database credentials |
| `neo4j-database` | Target database name |
| `mcp-api-key` | Static API key for client auth |

### Limitations

1. **Single Identity**: All clients share the same Neo4j credentials regardless of who is calling
2. **Static Credentials**: API key rotation requires redeployment or manual update
3. **No SSO Integration**: Cannot leverage enterprise identity providers
4. **No Audit Trail**: Cannot track which user made which request at the Neo4j level
5. **Additional Container**: Nginx proxy adds resource consumption and complexity
6. **Custom Token Validation**: Lua-based validation is custom code to maintain

---

## Proposed Architecture with Bearer Authentication

### Single-Container Model

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Azure Container Apps                                                     │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Neo4j MCP Server                              │   │
│  │                    Port 8000 (external)                          │   │
│  │                                                                  │   │
│  │   • Receives JWT bearer tokens from clients                      │   │
│  │   • Passes tokens directly to Neo4j via BearerAuth              │   │
│  │   • Neo4j validates tokens against identity provider JWKS       │   │
│  │   • Query execution uses caller's identity                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Bearer Token Authentication Flow

```
┌───────────────┐     ┌──────────────────┐     ┌─────────────────┐
│    Client     │     │ Identity Provider│     │   MCP Server    │
│  (AI Agent)   │     │ (Entra ID/Okta)  │     │   (Azure)       │
└──────┬────────┘     └────────┬─────────┘     └────────┬────────┘
       │                       │                        │
       │ 1. Auth Request       │                        │
       │  (client credentials) │                        │
       │──────────────────────>│                        │
       │                       │                        │
       │ 2. JWT Access Token   │                        │
       │<──────────────────────│                        │
       │                       │                        │
       │ 3. MCP Request with Bearer Token               │
       │   Authorization: Bearer <jwt>                  │
       │───────────────────────────────────────────────>│
       │                                                │
       │                       │  4. Query with         │
       │                       │     BearerAuth(token)  │
       │                       │<───────────────────────│
       │                       │                        │
       │                       │  5. Validate JWT       │
       │                       │     via JWKS endpoint  │
       │                       │                        │
       │                       │  6. Query as           │
       │                       │     authenticated user │
       │                       │───────────────────────>│ Neo4j
       │                                                │
       │ 7. Response                                    │
       │<───────────────────────────────────────────────│
```

### Key Architectural Changes

1. **Remove Nginx Proxy Container**: Single MCP server container handles all traffic
2. **External Port on MCP Server**: Container App ingress routes directly to port 8000
3. **No Static API Key**: Authentication delegated to identity provider
4. **Per-Request Identity**: Each request carries the caller's JWT and executes as that identity
5. **Neo4j Validates Tokens**: MCP server passes tokens through; Neo4j validates against IdP

---

## Why Bearer Token Authentication

### Enterprise Benefits

| Benefit | Description |
|---------|-------------|
| **SSO Integration** | Leverage existing Microsoft Entra ID, Okta, or other OIDC providers |
| **User-Level Audit** | Neo4j logs show which user ran which query |
| **Role-Based Access** | JWT claims map to Neo4j roles for fine-grained permissions |
| **Automatic Expiration** | Tokens expire; no credential rotation needed |
| **Zero Trust Ready** | Every request carries proof of identity |
| **Reduced Attack Surface** | No static secrets to leak or guess |

### Operational Benefits

| Benefit | Description |
|---------|-------------|
| **Simpler Architecture** | One container instead of two |
| **Less Custom Code** | Remove Lua-based authentication logic |
| **Lower Resource Usage** | Eliminate Nginx container overhead |
| **Standard Protocol** | OAuth 2.0 / OIDC are well-understood |
| **Identity Provider Features** | MFA, conditional access, group sync |

### Use Cases

1. **Machine-to-Machine (M2M)**: Backend services authenticate with client credentials grant
2. **User Delegation**: Interactive applications pass user tokens for personalized access
3. **Multi-Tenant**: Different tenants use different IdP configurations
4. **Compliance**: Meet audit requirements with user-level query attribution

---

## Deployment Changes

### Command Line Interface

Add the `--bearer` flag to the deployment script:

```bash
# Current deployment (API key authentication)
./scripts/deploy.sh

# New deployment with bearer token authentication
./scripts/deploy.sh --bearer
```

### Environment Variable Changes

**Current (API Key Mode):**
```bash
NEO4J_URI=neo4j+s://xxx.databases.neo4j.io
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=xxx
NEO4J_DATABASE=neo4j
MCP_API_KEY=xxx
```

**Bearer Mode:**
```bash
NEO4J_URI=neo4j+s://xxx.databases.neo4j.io
NEO4J_DATABASE=neo4j

# No username/password - credentials come from bearer tokens
# No MCP_API_KEY - authentication via identity provider
```

### Deploy Script Modifications

The deploy script would need to support both modes:

**Phase 1: Foundation Deployment**

In bearer mode, skip creation of the `mcp-api-key` secret in Key Vault since API key authentication is not used.

**Phase 2: Container Configuration**

In bearer mode:
- Deploy only the MCP server container (skip auth proxy)
- Configure external ingress directly to port 8000
- Do not inject NEO4J_USERNAME or NEO4J_PASSWORD environment variables
- The MCP server starts without static credentials (HTTP mode with per-request auth)

**Phase 3: Output Generation**

Generate different MCP_ACCESS.json content depending on mode:

API Key Mode:
```json
{
  "authentication": {
    "type": "api_key",
    "header": "Authorization",
    "prefix": "Bearer"
  }
}
```

Bearer Mode:
```json
{
  "authentication": {
    "type": "bearer_token",
    "description": "Obtain JWT from your identity provider",
    "header": "Authorization",
    "prefix": "Bearer",
    "identity_provider": {
      "type": "oidc",
      "note": "Configure your IdP to issue tokens for Neo4j"
    }
  }
}
```

---

## Infrastructure Changes

### Bicep Template Modifications

**container-app.bicep** would need conditional logic for bearer mode:

**API Key Mode (current):**
- Two containers (auth-proxy, mcp-server)
- Ingress targets port 8080 (Nginx)
- MCP server on localhost:8000
- All secrets injected as environment variables

**Bearer Mode:**
- Single container (mcp-server only)
- Ingress targets port 8000 directly
- MCP server exposed externally
- Only non-credential secrets injected (NEO4J_URI, NEO4J_DATABASE)
- NEO4J_MCP_TRANSPORT set to "http"

### Key Vault Secret Changes

In bearer mode, the following secrets would no longer be needed:
- `neo4j-username` (credentials from tokens)
- `neo4j-password` (credentials from tokens)
- `mcp-api-key` (no API key authentication)

Retained secrets:
- `neo4j-uri` (database connection string)
- `neo4j-database` (target database name)

### Container Resources

**API Key Mode:**
```
auth-proxy:  0.25 CPU, 0.5Gi memory
mcp-server:  0.50 CPU, 1.0Gi memory
Total:       0.75 CPU, 1.5Gi memory
```

**Bearer Mode:**
```
mcp-server:  0.50 CPU, 1.0Gi memory (or slightly more)
Total:       0.50 CPU, 1.0Gi memory
```

Resource savings: approximately 33% CPU and 33% memory reduction.

---

## Identity Provider Integration

### Prerequisites for Bearer Mode

Bearer token authentication requires Neo4j to be configured for OIDC. This means:

1. **Neo4j Enterprise Edition** (self-hosted) with SSO configured, OR
2. **Neo4j Aura Enterprise** with SSO enabled (verify driver-level bearer auth support)

### Neo4j Configuration (Self-Hosted)

For self-hosted Neo4j Enterprise, add to `neo4j.conf`:

```properties
# Enable OIDC authentication
dbms.security.authentication_providers=oidc-azure,native
dbms.security.authorization_providers=oidc-azure,native

# Azure Entra ID configuration
dbms.security.oidc.azure.well_known_discovery_uri=https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration
dbms.security.oidc.azure.audience={app-id}
dbms.security.oidc.azure.claims.username=preferred_username
dbms.security.oidc.azure.claims.groups=groups

# Map Azure AD groups to Neo4j roles
dbms.security.oidc.azure.authorization.group_to_role_mapping=neo4j-admins=admin;neo4j-readers=reader
```

### Supported Identity Providers

The deployment could work with any OIDC-compliant identity provider:

| Provider | Notes |
|----------|-------|
| Microsoft Entra ID | Native Azure integration, common for Azure deployments |
| Okta | Full OIDC support, enterprise-ready |
| Auth0 | Developer-friendly, easy setup |
| Keycloak | Open-source, self-hosted option |
| Ping Identity | Enterprise identity management |
| AWS Cognito | For hybrid AWS/Azure environments |

### Client Token Acquisition

Clients would obtain tokens using the OAuth 2.0 client credentials grant:

```python
import msal

app = msal.ConfidentialClientApplication(
    client_id="your-app-id",
    authority="https://login.microsoftonline.com/your-tenant-id",
    client_credential="your-client-secret"
)

result = app.acquire_token_for_client(scopes=["api://your-app-id/.default"])
token = result["access_token"]

# Use token with MCP server
response = requests.post(
    "https://your-mcp-server.azurecontainerapps.io/mcp",
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    },
    json={
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {"name": "read-cypher", "arguments": {"query": "MATCH (n) RETURN count(n)"}},
        "id": 1
    }
)
```

---

## Migration Path

### Option 1: Fresh Deployment

Deploy a new environment with `--bearer` flag. Suitable for new projects or when breaking changes are acceptable.

```bash
./scripts/deploy.sh --bearer
```

### Option 2: Parallel Deployment

Run both authentication modes in separate environments during transition:

```bash
# Keep existing API key deployment
./scripts/deploy.sh

# Deploy bearer mode to separate resource group
AZURE_RESOURCE_GROUP=neo4j-mcp-bearer-rg ./scripts/deploy.sh --bearer
```

### Option 3: Mode Switching

Add infrastructure to switch modes on an existing deployment. This would require:

1. Updating Key Vault secrets
2. Redeploying the Container App with different configuration
3. Updating client configurations

### Rollback Procedure

If bearer mode has issues, revert to API key mode:

```bash
# Redeploy without --bearer flag
./scripts/deploy.sh
```

The script would need to detect the mode change and:
1. Recreate the `mcp-api-key` secret
2. Deploy both containers again
3. Reconfigure ingress to port 8080

---

## Security Considerations

### Advantages of Bearer Mode

1. **No Static Secrets**: Eliminates long-lived API keys that could be compromised
2. **Token Expiration**: JWTs have built-in expiry (typically 1 hour)
3. **Identity Provider Controls**: MFA, conditional access, impossible travel detection
4. **Cryptographic Verification**: Tokens signed with asymmetric keys
5. **Audit Trail**: User identity recorded in Neo4j logs
6. **Revocation**: Disable user in IdP immediately revokes access

### Security Risks to Address

1. **Token Exposure**: JWT tokens in transit must be protected (HTTPS required)
2. **Client Secret Management**: M2M client secrets need secure storage
3. **JWKS Availability**: Neo4j must reach IdP's JWKS endpoint
4. **Token Caching**: Clients should cache tokens appropriately
5. **Audience Validation**: Ensure tokens are issued for the correct audience

### Recommended Security Controls

1. **TLS Everywhere**: Container Apps ingress with HTTPS, Neo4j with encrypted connection
2. **Network Segmentation**: Consider private endpoints for Neo4j
3. **Minimum Scope**: Issue tokens with minimum required permissions
4. **Short Token Lifetime**: Use short-lived access tokens (1 hour or less)
5. **Monitor Failed Auth**: Alert on authentication failures

### Comparison: API Key vs Bearer Token

| Aspect | API Key | Bearer Token |
|--------|---------|--------------|
| **Lifetime** | Indefinite until rotated | Short (1 hour typical) |
| **Rotation** | Manual process | Automatic via token refresh |
| **Identity** | Shared across all callers | Per-caller identity |
| **Revocation** | Requires key rotation | Disable user in IdP |
| **MFA Support** | Not applicable | Supported via IdP |
| **Audit** | API key used | User identity logged |
| **Complexity** | Simple to implement | Requires IdP setup |

---

## Operational Impact

### Monitoring Changes

**Removed Metrics (Bearer Mode):**
- Auth proxy container health
- Auth proxy error rate
- API key validation failures

**New Metrics (Bearer Mode):**
- Token validation at Neo4j
- IdP JWKS endpoint latency
- Token expiration events

### Health Check Changes

**API Key Mode:**
- `/health` - Nginx container health
- `/ready` - MCP server connectivity

**Bearer Mode:**
- Health check directly on MCP server `/mcp` endpoint
- Consider adding dedicated health endpoint to MCP server

### Log Changes

**Removed Logs:**
- Nginx access logs
- Nginx error logs
- Lua authentication logs

**Enhanced Logs:**
- User identity in MCP server logs
- Neo4j authentication events
- Token validation results

### Cost Impact

Bearer mode reduces costs through:
- One fewer container (less compute)
- Smaller container image footprint
- Reduced network traffic (no proxy hop)

However, consider:
- Potential IdP API call costs (usually minimal)
- Increased Neo4j query logging storage

---

## Decision Points

Before implementing bearer token authentication, the following decisions need to be made:

### 1. Target Environments

**Question**: Which Neo4j deployments will use bearer mode?

**Options**:
- Neo4j Aura Enterprise with SSO (verify driver-level bearer auth support with Neo4j)
- Self-hosted Neo4j Enterprise with OIDC configured
- Both, with deployment-time selection

### 2. Identity Provider

**Question**: Which identity provider will be the primary target?

**Options**:
- Microsoft Entra ID (natural fit for Azure deployment)
- Okta (common enterprise choice)
- Generic OIDC (support any compliant provider)
- All of the above with configuration flexibility

### 3. Backward Compatibility

**Question**: How should the deployment handle existing API key deployments?

**Options**:
- Completely separate modes (cannot mix)
- Migration tooling to convert API key to bearer mode
- Support both modes simultaneously (complex)

### 4. Health Endpoints

**Question**: Should health endpoints require authentication in bearer mode?

**Options**:
- No authentication (current behavior for `/health` and `/ready`)
- Optional authentication
- Different endpoints for authenticated vs public health checks

### 5. Rate Limiting

**Question**: How should rate limiting work without Nginx?

**Options**:
- Rely on Azure Container Apps rate limiting
- Add rate limiting to MCP server code
- Use Azure API Management in front of Container Apps
- Accept no rate limiting (rely on IdP and Neo4j controls)

### 6. Fallback Authentication

**Question**: Should bearer mode support fallback to basic auth?

The Neo4j MCP server already supports both bearer tokens and basic auth in HTTP mode. The question is whether the deployment should:

**Options**:
- Bearer only (strictest)
- Bearer preferred, basic auth fallback (flexible)
- Configurable at deployment time

---

## Appendix: MCP Server Authentication Capabilities

The Neo4j MCP server (from the `/Users/ryanknight/projects/mcp` codebase) already supports bearer token authentication in HTTP mode. The relevant implementation details:

### Middleware Authentication Flow

The server's `authMiddleware` function (in `internal/server/middleware.go`) processes authentication in this order:

1. Check if request method requires authentication (`tools/call` requires auth)
2. Look for `Authorization: Bearer <token>` header
3. If bearer token found, store in request context
4. Fall back to basic auth if no bearer token
5. Fall back to environment variable credentials if no auth headers
6. Return 401 only for methods that require auth when no credentials available

### Bearer Token Handling

When a bearer token is provided:

1. Token extracted from `Authorization: Bearer <token>` header
2. Token stored in request context via `auth.WithBearerToken()`
3. Database service retrieves token via `auth.GetBearerToken()`
4. Token passed to Neo4j driver via `neo4j.BearerAuth(token)`
5. Neo4j validates token against configured OIDC provider

### Methods Requiring Authentication

Only `tools/call` requires authentication. Other methods like `initialize`, `tools/list`, and `ping` are accessible without credentials, enabling health checks and capability discovery.

---

## Conclusion

Adding bearer token authentication support to the Azure Neo4j MCP deployment would provide significant benefits for enterprise environments:

1. **Security**: Eliminates static API keys, enables SSO/MFA
2. **Audit**: User-level query attribution
3. **Simplicity**: Removes custom Nginx proxy code
4. **Cost**: Reduces container resource consumption
5. **Standards**: Uses industry-standard OAuth 2.0/OIDC

The Neo4j MCP server already has the necessary authentication capabilities built in. The deployment changes primarily involve:

1. Adding a `--bearer` flag to the deployment script
2. Conditionally deploying one vs two containers
3. Adjusting environment variable injection
4. Updating the generated MCP_ACCESS.json output

The main prerequisite is that the target Neo4j instance must be configured for OIDC authentication, which requires Neo4j Enterprise Edition (self-hosted) or potentially Neo4j Aura Enterprise with SSO.
