# Identity Provider Setup Guide

This guide covers configuring identity providers for bearer token authentication with the Neo4j MCP Server.

## Overview

Bearer token authentication requires coordination between three components:

1. **Identity Provider (IdP)**: Issues JWT tokens to clients
2. **Neo4j Database**: Validates tokens and maps claims to roles
3. **MCP Server**: Passes tokens through to Neo4j

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│    Client    │────>│  Identity    │────>│  MCP Server  │────>│    Neo4j     │
│  (AI Agent)  │     │  Provider    │     │   (Azure)    │     │  (OIDC)      │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       │                    │                    │                    │
       │ 1. Auth Request    │                    │                    │
       │───────────────────>│                    │                    │
       │                    │                    │                    │
       │ 2. JWT Token       │                    │                    │
       │<───────────────────│                    │                    │
       │                    │                    │                    │
       │ 3. MCP Request with Bearer Token        │                    │
       │────────────────────────────────────────>│                    │
       │                    │                    │                    │
       │                    │                    │ 4. Query + Token   │
       │                    │                    │───────────────────>│
       │                    │                    │                    │
       │                    │                    │ 5. Validate via    │
       │                    │<─ ─ ─ ─ ─ ─ ─ ─ ─ ─│    JWKS endpoint   │
       │                    │                    │                    │
```

---

## Microsoft Entra ID (Azure AD)

Microsoft Entra ID is recommended for Azure deployments due to native integration.

### Step 1: Register an Application

1. Go to [Azure Portal](https://portal.azure.com) > Microsoft Entra ID > App registrations
2. Click "New registration"
3. Configure:
   - **Name**: `Neo4j MCP Server`
   - **Supported account types**: Choose based on your needs
   - **Redirect URI**: Leave blank for service-to-service auth
4. Click "Register"
5. Note the **Application (client) ID** and **Directory (tenant) ID**

### Step 2: Create a Client Secret

1. In your app registration, go to "Certificates & secrets"
2. Click "New client secret"
3. Add a description and expiration
4. Copy the secret value immediately (shown only once)

### Step 3: Configure API Permissions (Optional)

For basic authentication, no additional permissions are needed. The app will authenticate using its own identity.

### Step 4: Configure Neo4j for Entra ID

Add to your `neo4j.conf`:

```properties
# Enable OIDC authentication
dbms.security.authentication_providers=oidc-azure,native
dbms.security.authorization_providers=oidc-azure,native

# Azure Entra ID configuration
dbms.security.oidc.azure.display_name=Azure AD
dbms.security.oidc.azure.auth_flow=pkce
dbms.security.oidc.azure.well_known_discovery_uri=https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration
dbms.security.oidc.azure.audience={application-id}
dbms.security.oidc.azure.claims.username=preferred_username
dbms.security.oidc.azure.claims.groups=groups
dbms.security.oidc.azure.params=scope=openid profile email

# Map Entra ID groups to Neo4j roles
# Create groups in Entra ID: neo4j-admins, neo4j-readers
dbms.security.oidc.azure.authorization.group_to_role_mapping=neo4j-admins=admin;neo4j-readers=reader
```

Replace:
- `{tenant-id}`: Your Entra ID tenant ID
- `{application-id}`: Your app registration's Application ID

### Step 5: Obtain Tokens

**Using MSAL (Python):**

```python
from msal import ConfidentialClientApplication

app = ConfidentialClientApplication(
    client_id="your-application-id",
    authority="https://login.microsoftonline.com/your-tenant-id",
    client_credential="your-client-secret"
)

result = app.acquire_token_for_client(
    scopes=["api://your-application-id/.default"]
)

token = result["access_token"]
```

**Using Azure CLI:**

```bash
# For user tokens (interactive)
az login
TOKEN=$(az account get-access-token --resource api://your-application-id --query accessToken -o tsv)

# For service principal tokens
az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID
TOKEN=$(az account get-access-token --resource api://your-application-id --query accessToken -o tsv)
```

---

## Okta

Okta is a popular enterprise identity provider with excellent OIDC support.

### Step 1: Create an Application

1. Go to Okta Admin Console > Applications > Create App Integration
2. Select "API Services" (for machine-to-machine) or "OIDC" (for user auth)
3. Configure:
   - **Name**: `Neo4j MCP Server`
   - **Grant type**: Client Credentials (for M2M)
4. Note the **Client ID** and **Client secret**

### Step 2: Configure Authorization Server

1. Go to Security > API > Authorization Servers
2. Use the "default" server or create a custom one
3. Add a scope for Neo4j (e.g., `neo4j`)
4. Note the **Issuer URI**

### Step 3: Configure Neo4j for Okta

Add to your `neo4j.conf`:

```properties
# Enable OIDC authentication
dbms.security.authentication_providers=oidc-okta,native
dbms.security.authorization_providers=oidc-okta,native

# Okta configuration
dbms.security.oidc.okta.display_name=Okta
dbms.security.oidc.okta.auth_flow=pkce
dbms.security.oidc.okta.well_known_discovery_uri=https://your-domain.okta.com/.well-known/openid-configuration
dbms.security.oidc.okta.audience=api://default
dbms.security.oidc.okta.claims.username=sub
dbms.security.oidc.okta.claims.groups=groups

# Map Okta groups to Neo4j roles
dbms.security.oidc.okta.authorization.group_to_role_mapping=neo4j-admins=admin;neo4j-readers=reader
```

### Step 4: Obtain Tokens

**Using requests (Python):**

```python
import requests

response = requests.post(
    "https://your-domain.okta.com/oauth2/default/v1/token",
    data={
        "grant_type": "client_credentials",
        "client_id": "your-client-id",
        "client_secret": "your-client-secret",
        "scope": "neo4j"
    }
)

token = response.json()["access_token"]
```

---

## Auth0

Auth0 provides a developer-friendly identity platform.

### Step 1: Create an Application

1. Go to Auth0 Dashboard > Applications > Create Application
2. Select "Machine to Machine Applications"
3. Configure API permissions
4. Note the **Client ID** and **Client Secret**

### Step 2: Create an API

1. Go to Applications > APIs > Create API
2. Set:
   - **Name**: `Neo4j MCP API`
   - **Identifier**: `https://neo4j-mcp`
3. Note the **Identifier** (used as audience)

### Step 3: Configure Neo4j for Auth0

Add to your `neo4j.conf`:

```properties
# Enable OIDC authentication
dbms.security.authentication_providers=oidc-auth0,native
dbms.security.authorization_providers=oidc-auth0,native

# Auth0 configuration
dbms.security.oidc.auth0.display_name=Auth0
dbms.security.oidc.auth0.auth_flow=pkce
dbms.security.oidc.auth0.well_known_discovery_uri=https://your-tenant.auth0.com/.well-known/openid-configuration
dbms.security.oidc.auth0.audience=https://neo4j-mcp
dbms.security.oidc.auth0.claims.username=sub

# Auth0 uses custom claims for roles
dbms.security.oidc.auth0.claims.groups=https://your-namespace/roles
```

### Step 4: Obtain Tokens

```python
import requests

response = requests.post(
    "https://your-tenant.auth0.com/oauth/token",
    json={
        "grant_type": "client_credentials",
        "client_id": "your-client-id",
        "client_secret": "your-client-secret",
        "audience": "https://neo4j-mcp"
    }
)

token = response.json()["access_token"]
```

---

## Keycloak (Self-Hosted)

Keycloak is an open-source identity provider that can be self-hosted.

### Step 1: Create a Realm and Client

1. Create a new realm or use existing
2. Go to Clients > Create client
3. Configure:
   - **Client type**: OpenID Connect
   - **Client ID**: `neo4j-mcp`
   - **Client authentication**: On (for confidential client)
4. Generate and note the client secret

### Step 2: Configure Neo4j for Keycloak

Add to your `neo4j.conf`:

```properties
# Enable OIDC authentication
dbms.security.authentication_providers=oidc-keycloak,native
dbms.security.authorization_providers=oidc-keycloak,native

# Keycloak configuration
dbms.security.oidc.keycloak.display_name=Keycloak
dbms.security.oidc.keycloak.auth_flow=pkce
dbms.security.oidc.keycloak.well_known_discovery_uri=https://keycloak.example.com/realms/your-realm/.well-known/openid-configuration
dbms.security.oidc.keycloak.audience=neo4j-mcp
dbms.security.oidc.keycloak.claims.username=preferred_username
dbms.security.oidc.keycloak.claims.groups=groups
```

---

## Troubleshooting

### Token Validation Fails

1. **Check audience**: Ensure the token's `aud` claim matches Neo4j's configured audience
2. **Check issuer**: Verify the `iss` claim matches the expected issuer
3. **Check expiration**: Tokens must not be expired
4. **Check JWKS endpoint**: Neo4j must be able to reach the IdP's JWKS endpoint

### "User not found" Errors

1. **Check username claim**: Ensure the claim configured for username exists in the token
2. **Enable local user requirement**: If `dbms.security.require_local_user=true`, create users in Neo4j first

### Role Mapping Issues

1. **Check group claims**: Verify the groups claim contains expected values
2. **Check mapping syntax**: Format is `group1=role1;group2=role2`
3. **Create roles first**: Neo4j roles must exist before mapping

### Network Issues

1. **Check JWKS accessibility**: Neo4j must reach the IdP's JWKS endpoint
2. **Check firewall rules**: Allow outbound HTTPS to the IdP
3. **Check DNS resolution**: Verify IdP hostname resolves correctly

### Debugging

Enable debug logging in Neo4j:

```properties
dbms.logs.security.level=DEBUG
```

Check Neo4j security log for detailed authentication errors.

---

## Security Best Practices

1. **Short token lifetime**: Use tokens with 1-hour or shorter expiration
2. **Rotate client secrets**: Regularly rotate application secrets
3. **Use managed identities**: In Azure, prefer managed identities over client secrets
4. **Minimum permissions**: Grant only necessary roles to users/applications
5. **Monitor authentication**: Set up alerts for failed authentication attempts
6. **Network security**: Use private endpoints where possible
