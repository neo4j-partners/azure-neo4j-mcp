# Authentication Proposal for Neo4j MCP Server on Azure Container Apps

This document proposes authentication approaches for the Neo4j MCP server deployed on Azure Container Apps. The goal is to secure access to the MCP container while keeping Neo4j authentication simple using standard username/password credentials.

## Current Architecture

```
Client (Claude Desktop, VS Code, etc.)
    |
    | Bearer Token (API Key)
    v
Azure Container App Ingress (HTTPS)
    |
    v
Nginx Auth Proxy (port 8080)
    |  1. Validates Bearer token
    |  2. Injects Basic Auth header
    |
    | Basic Auth (NEO4J_USERNAME:NEO4J_PASSWORD)
    v
Neo4j MCP Server (port 8000, HTTP mode)
    |
    | Basic Auth credentials
    v
Neo4j Database (Aura or self-hosted)
```

## Authentication Layers

### Layer 1: Client to Container (Protecting the MCP Server)

This layer authenticates clients calling the MCP server endpoint. Options from simplest to most robust:

#### Option A: Static API Key (Current - Simplest)

**How it works:**
- A static API key is stored in Azure Key Vault
- Clients include the key as a Bearer token: `Authorization: Bearer <API_KEY>`
- Nginx validates the key before forwarding requests

**Pros:**
- Simple to implement and use
- Works with any MCP client
- No Azure AD integration required

**Cons:**
- Key must be shared with all clients
- No per-user tracking or revocation
- Key rotation requires client updates

**Configuration:**
```bash
# In .env
MCP_API_KEY=your-secure-random-string-here
```

**Client usage:**
```json
{
  "mcpServers": {
    "neo4j": {
      "url": "https://your-app.azurecontainerapps.io/mcp",
      "headers": {
        "Authorization": "Bearer your-api-key-here"
      }
    }
  }
}
```

#### Option B: Azure Entra ID (More Robust)

**How it works:**
- Register an App in Azure Entra ID
- Clients authenticate with Entra ID and get an access token
- Container App validates the token using Entra ID

**Implementation approaches:**

##### B1: Container Apps Built-in Auth (Easy Auth)

Azure Container Apps has built-in authentication that can validate Entra ID tokens automatically.

**Pros:**
- Managed by Azure, minimal code
- Supports user identity and service principals
- Token validation handled automatically

**Cons:**
- Adds complexity to client configuration
- MCP clients need OAuth flow support (or pre-obtained tokens)
- Requires Entra ID app registration

**Setup:**
1. Register an App in Entra ID
2. Enable authentication on Container App via Azure Portal or Bicep
3. Configure allowed client applications

##### B2: Manual Token Validation in Nginx

Validate Entra ID tokens in the nginx proxy using Lua.

**Pros:**
- Full control over validation logic
- Can combine with API key fallback

**Cons:**
- More complex implementation
- Must handle token refresh, JWKS rotation

#### Option C: API Management (Enterprise)

Use Azure API Management in front of the Container App.

**Pros:**
- Rich policy engine (rate limiting, quotas, analytics)
- Multiple authentication options
- Developer portal for API key management

**Cons:**
- Additional cost
- More infrastructure to manage
- May be overkill for simple deployments

### Layer 2: Container to Neo4j (Database Authentication)

This layer authenticates the MCP server to the Neo4j database. This should ALWAYS use standard Neo4j credentials.

**Current approach (Recommended):**
- Neo4j credentials stored in Azure Key Vault
- Passed to the auth proxy as environment variables
- Auth proxy injects Basic Auth header to MCP server
- MCP server passes credentials to Neo4j

**Why NOT use Bearer/SSO for Neo4j:**
- Requires Neo4j Enterprise with SSO/OAuth configuration
- Much more complex setup
- Most Neo4j deployments (including Aura) use username/password
- Standard credentials work with all Neo4j editions

## Recommendations

### For Development/Demo (Simplest)

Use **Option A: Static API Key**

1. Generate a secure API key:
   ```bash
   openssl rand -base64 32
   ```

2. Add to `.env`:
   ```bash
   MCP_API_KEY=your-generated-key
   NEO4J_URI=neo4j+s://xxxxx.databases.neo4j.io
   NEO4J_USERNAME=neo4j
   NEO4J_PASSWORD=your-neo4j-password
   ```

3. Deploy and share the API key with authorized users

### For Production (More Secure)

Use **Option B1: Container Apps Easy Auth** with Entra ID

1. Register an App in Entra ID
2. Configure Container App authentication
3. Issue tokens to authorized clients/applications

### For Enterprise (Full Featured)

Use **Option C: API Management**

1. Deploy API Management instance
2. Configure authentication policies
3. Use developer portal for API key management

## Environment Variables Reference

These variables match the official Neo4j MCP server configuration from https://github.com/neo4j/mcp:

```bash
# Neo4j Connection (Required)
NEO4J_URI=neo4j+s://xxxxx.databases.neo4j.io
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=your-password
NEO4J_DATABASE=neo4j

# MCP Server Authentication (Required for container deployment)
MCP_API_KEY=your-secure-api-key

# Azure Configuration (Required)
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_RESOURCE_GROUP=neo4j-mcp-demo-rg
AZURE_LOCATION=eastus
```

## Summary

| Approach | Complexity | Security | Best For |
|----------|------------|----------|----------|
| API Key | Low | Medium | Dev/Demo, small teams |
| Entra ID Easy Auth | Medium | High | Production, enterprise |
| API Management | High | Highest | Enterprise, public APIs |

**Key principle:** Use Bearer token/Entra ID for protecting access to the MCP container. Always use standard username/password (Basic Auth) for Neo4j database authentication.
