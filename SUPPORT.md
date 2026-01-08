# Neo4j Support Request: Aura SSO with M2M (Client Credentials) Authentication

## Email to Neo4j Support

**Subject:** Does Neo4j Aura SSO support Machine-to-Machine (Client Credentials) authentication with Azure Entra ID?

---

Hi Neo4j Support Team,

I'm working on deploying the official Neo4j MCP server (https://github.com/neo4j/mcp) to Azure Container Apps to enable AI agents to query Neo4j Aura databases. I have a question about Aura SSO capabilities.

### The Question

Does Neo4j Aura SSO support Machine-to-Machine (M2M) authentication using OAuth 2.0 Client Credentials flow with Azure Entra ID? Specifically, can a service/application authenticate to Aura using a JWT access token obtained via `client_credentials` grant (no user involved)?

### Problem Summary

I successfully:
1. Configured an Azure Entra ID app registration for Neo4j Aura SSO
2. Set up SSO in the Aura console with the Entra discovery URI
3. Obtained a valid JWT access token using MSAL's `acquire_token_for_client()` (Client Credentials flow)

However, when connecting to Aura with the bearer token:
```python
driver = GraphDatabase.driver(uri, auth=bearer_auth(access_token))
```

I receive:
```
Neo.ClientError.Security.Unauthorized
The client is unauthorized due to authentication failure.
```

The token is valid (verified claims: correct issuer, audience, not expired). Aura seems to reject M2M tokens.

### Why M2M Matters

The Neo4j MCP server (https://github.com/neo4j/mcp) is designed for AI agents to query graph databases. In production:
- AI agents authenticate as **applications**, not users
- Client Credentials flow is the standard OAuth pattern for server-to-server auth
- No human is present to perform interactive login

If Aura only supports user-based SSO (Authorization Code / ROPC flows), the MCP server would need user credentials, which defeats the purpose of SSO for AI/automation use cases.

### Our Setup

**Neo4j Aura SSO Configuration (following official docs):**

I followed the official Neo4j Aura SSO documentation:
https://neo4j.com/docs/aura/security/single-sign-on/#_microsoft_entra_id_sso

Steps completed:
1. Created Azure Entra ID app registration with redirect URI `https://login.neo4j.com/login/callback`
2. Created client secret in Azure Portal
3. In Aura Console > Organization > Security > Single Sign On:
   - Added new Microsoft Entra ID configuration
   - Entered Client ID, Client Secret, and Discovery URI
   - Checked **"Use as login method for instances within Projects in this Organization"**
4. Created a **Business Critical** instance in that project specifically for SSO testing

**Azure Entra ID App Registration:**
- App type: Confidential client (with client secret)
- Application ID URI: `api://{client_id}` (configured in "Expose an API")
- Redirect URI: `https://login.neo4j.com/login/callback`
- API permissions: `openid`, `profile`, `email`, `User.Read`

**Token Acquisition (Python/MSAL):**
```python
app = msal.ConfidentialClientApplication(
    client_id,
    authority=f"https://login.microsoftonline.com/{tenant_id}",
    client_credential=client_secret,
)

# M2M scope per Neo4j field team example:
# https://github.com/neo4j-field/entraid-programmatic-sso
scopes = [f"api://{client_id}/.default"]
result = app.acquire_token_for_client(scopes=scopes)
access_token = result["access_token"]
```

**Neo4j Connection:**
```python
driver = GraphDatabase.driver(
    "neo4j+s://xxxx.databases.neo4j.io",
    auth=bearer_auth(access_token)
)
```

**Token Claims (decoded):**
```json
{
  "iss": "https://login.microsoftonline.com/{tenant_id}/v2.0",
  "aud": "api://{client_id}",
  "sub": "{app_object_id}",
  "azp": "{client_id}",
  "roles": [],
  "scp": null
}
```

**Neo4j Aura SSO Configuration:**
- Provider: Microsoft Entra ID
- Client ID: (matches Entra app)
- Client Secret: (Entra app secret)
- Discovery URI: `https://login.microsoftonline.com/{tenant_id}/v2.0/.well-known/openid-configuration`

### Reference

I followed the pattern from the Neo4j Field Team's entraid-programmatic-sso example:
https://github.com/neo4j-field/entraid-programmatic-sso

This example shows M2M working with Neo4j Enterprise. My question is whether the same pattern works with Aura.

### Questions

1. Does Aura SSO support M2M/Client Credentials authentication, or only user-based flows?
2. If M2M is supported, is additional Aura configuration required (role mapping, app roles, etc.)?
3. If M2M is NOT supported, is this a planned feature? What's the recommended approach for AI/automation scenarios?

Thank you for your help!

---

## Supporting Information

### Test Script Used

`test-sso/test_m2m.py` - Tests M2M authentication flow:

```python
#!/usr/bin/env python3
"""
Test Neo4j Aura SSO with Azure Entra ID using M2M (Client Credentials) flow.
"""

import msal
from neo4j import GraphDatabase, bearer_auth

def get_m2m_token(tenant_id, client_id, client_secret):
    authority = f"https://login.microsoftonline.com/{tenant_id}"
    app = msal.ConfidentialClientApplication(
        client_id,
        authority=authority,
        client_credential=client_secret,
    )
    scopes = [f"api://{client_id}/.default"]
    result = app.acquire_token_for_client(scopes=scopes)
    return result

def main():
    # ... load config from .env ...
    result = get_m2m_token(tenant_id, client_id, client_secret)
    access_token = result["access_token"]

    # This fails with Unauthorized
    driver = GraphDatabase.driver(neo4j_uri, auth=bearer_auth(access_token))
    with driver.session() as session:
        session.run("RETURN 1")
```

### How Neo4j MCP Server Uses Bearer Auth

From `github.com/neo4j/mcp`, the server passes bearer tokens directly to Neo4j:

```go
// internal/database/service.go
if token, hasBearerToken := auth.GetBearerToken(ctx); hasBearerToken {
    authToken := neo4j.BearerAuth(token)
    queryOptions = append(queryOptions, neo4j.ExecuteQueryWithAuthToken(authToken))
}
```

The MCP server does NOT validate tokens - it expects Neo4j to validate them via JWKS endpoints. This works with Neo4j Enterprise + OIDC configuration, but the question is whether Aura SSO performs the same validation for M2M tokens.

### Error Details

```
Neo.ClientError.Security.Unauthorized
message: The client is unauthorized due to authentication failure.
gql_status: 42NFF
gql_status_description: error: syntax error or access rule violation - permission/access denied
```

This suggests Aura validated the token format but rejected it - possibly because:
1. M2M tokens aren't supported
2. The `sub` claim (app ID) doesn't map to a known user
3. Additional Aura configuration is required

---

## M2M Token Validation Results

To confirm the Azure Entra ID M2M setup is correct (independent of Neo4j), I ran a comprehensive token validation script that verifies the token cryptographically using Azure's JWKS public keys.

**Validation Script:** `test-sso/validate_entra_m2m.py`

**Results:**

```
============================================================
VALIDATION SUMMARY
============================================================
  [OK] Create MSAL ConfidentialClientApplication
  [OK] Acquire M2M token
  [OK] Fetch OpenID configuration
  [OK] Fetch JWKS public keys
  [OK] Token has key ID (kid)
  [OK] Find matching public key
  [OK] Build RSA public key
  [OK] Verify signature (RS256)
  [OK] Verify expiration (exp)
  [OK] Verify issuer (iss)
  [OK] Verify audience (aud=api://31672429-2606-4eb9-ae46-d05d12b53304)

Total: 11 passed, 0 failed

============================================================
SUCCESS - Entra M2M Setup is Correct
============================================================

Your Azure Entra ID M2M configuration is valid:
  - Token acquired successfully
  - Signature verified with Azure's public key
  - Issuer and audience claims are correct
  - Token has not expired
```

**Conclusion:**

The Azure Entra ID M2M configuration is cryptographically valid. The token:
- Is properly signed by Azure (RS256, verified against JWKS)
- Has correct issuer (`https://sts.windows.net/{tenant_id}/`)
- Has correct audience (`api://{client_id}`)
- Is not expired

This confirms the issue is **not** with the Entra ID setup, but rather with how Neo4j Aura SSO handles M2M (Client Credentials) tokens.
