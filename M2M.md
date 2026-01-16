# M2M Authentication: Why SSO Doesn't Solve the Problem

## The Confusion

There's a fundamental misunderstanding in our approach. We've been conflating two very different things:

1. **SSO (Single Sign-On)**: Lets *humans* log in once and access multiple systems
2. **API Keys / Service Credentials**: Lets *machines* authenticate without human involvement

When we say "bearer token support" for the MCP server, we're actually talking about two different scenarios that look similar but are fundamentally different.

---

## What is SSO Actually For?

SSO exists to solve a human problem: "I don't want to remember 50 passwords for 50 different applications."

Here's what SSO looks like:
1. A person sits at their computer
2. They click "Sign in with Microsoft"
3. A browser window opens
4. They type their password (or use their fingerprint/face)
5. They get redirected back to the application
6. They're logged in

The key word here is **person**. There's a human in the loop. The human has to be present to authenticate.

This is what Neo4j Aura SSO provides. It lets humans log into Aura Console, Neo4j Browser, and other tools without creating a separate Neo4j password.

---

## What Does Machine-to-Machine (M2M) Actually Need?

An MCP server is a program. It runs on a server somewhere. There's no human sitting there to type a password or click through a browser login flow.

What does the MCP server need?
- A credential that proves it's allowed to access the database
- That credential should be easy to rotate if compromised
- No human interaction required

This is the **API key** pattern. Every major cloud service uses it:
- AWS uses Access Key ID + Secret Access Key
- Google Cloud uses Service Account JSON files
- Azure uses Service Principal credentials
- Stripe, Twilio, SendGrid all use API keys

---

## Why OAuth Bearer Tokens Don't Solve This

OAuth (which SSO uses under the hood) has a flow called "Client Credentials" that sounds like it should work for machines. We tried this. Here's what happens:

1. MCP server sends its client_id + client_secret to Azure Entra
2. Azure Entra gives back a JWT token
3. MCP server sends that token to Neo4j Aura
4. **Neo4j Aura rejects it**

Why? Because Neo4j Aura SSO is designed for the "Authorization Code" flow - the one where a human clicks through a browser. The tokens it expects contain things like:
- User's email address
- User's group memberships
- Human identity claims

Our machine token doesn't have any of that. It just says "I am an application called X."

Self-hosted Neo4j Enterprise has special configuration (`dbms.security.oidc.m2m.*`) specifically for machine tokens. Neo4j Aura doesn't expose this configuration.

---

## How Other Databases Solve This

### Supabase (PostgreSQL)
Uses **API keys**. You get two keys when you create a project:
- `anon` key (for public, limited access)
- `service_role` key (for backend services, full access)

Their MCP server just takes the `service_role` key directly. No OAuth dance, no tokens, no browser flows.

Reference: [Supabase API Keys](https://supabase.com/docs/guides/api/api-keys)

### MongoDB Atlas
Uses **API keys** (legacy) or **Service Accounts** (recommended). Their MCP server configuration looks like:
```json
{
  "apiClientId": "your-service-account-id",
  "apiClientSecret": "your-service-account-secret"
}
```
Behind the scenes, their service accounts use OAuth 2.0 Client Credentials flow - but the important thing is that MongoDB Atlas's backend *accepts* these machine tokens.

Reference: [MongoDB Atlas API Authentication](https://www.mongodb.com/docs/atlas/api/api-authentication/)

### Cloudflare D1
Uses **API tokens**. You create a token in the dashboard, scope it to specific permissions, and use it in your code.

Reference: [Cloudflare D1](https://developers.cloudflare.com/d1/)

### MotherDuck (DuckDB Cloud)
Uses **OAuth 2.1** for user authentication but mentions **"read scaling tokens"** for service accounts. They built a custom OAuth proxy because their identity provider (Auth0) doesn't natively support all MCP requirements.

Reference: [MotherDuck MCP Blog](https://motherduck.com/blog/dev-diary-building-mcp/)

---

## What Neo4j Aura Currently Offers

| Method | Who It's For | Works in MCP? |
|--------|--------------|---------------|
| **SSO (Entra ID, Okta, etc.)** | Humans logging in via browser | No - requires human interaction |
| **Username/Password** | Direct database access | Yes - but credentials must be managed |
| **Aura API Credentials** | Aura Console API (create instances, etc.) | No - this is for the *Aura platform*, not the *database* |

The gap: **There's no simple API key for database access.**

---

## What Neo4j Aura Would Need

To support M2M authentication properly, Neo4j Aura would need one of:

### Option 1: API Keys for Database Access
Like every other cloud database. You'd go to the Aura Console, click "Create API Key", scope it to a specific database and role, and get a string you can use directly:
```
NEO4J_API_KEY=aura_abc123xyz789...
```
The MCP server would send this in requests and Aura would validate it.

### Option 2: Service Accounts with Client Credentials
Similar to MongoDB Atlas's service accounts. You'd create a service account in Aura Console, get a client_id + client_secret, and the MCP server would exchange these for tokens that Aura *actually accepts* (not just Entra tokens that Aura ignores).

### Option 3: Expose M2M OIDC Configuration
Like self-hosted Neo4j Enterprise. Aura would allow configuring the `dbms.security.oidc.m2m.*` settings so that machine tokens from Entra/Okta are accepted.

---

## The MCP Specification Perspective

The MCP specification (as of 2025) says:
- **HTTP transport**: SHOULD use OAuth 2.1
- **STDIO transport**: SHOULD NOT use OAuth, just use environment variables

For database MCP servers running locally (STDIO), the spec explicitly says to just use credentials from the environment - like a username/password or API key stored in environment variables.

For remote MCP servers (HTTP), OAuth 2.1 is recommended, but this is primarily about authenticating *users* to the MCP server itself, not about how the MCP server authenticates to downstream services.

Reference: [MCP Authorization Tutorial](https://modelcontextprotocol.io/docs/tutorials/security/authorization)

---

## Why This Is Confusing

The confusion comes from OAuth/OIDC having multiple "flows":

| Flow | Who Uses It | Human Required? |
|------|-------------|-----------------|
| Authorization Code | Web apps, mobile apps | Yes - browser redirect |
| Authorization Code + PKCE | Single-page apps, native apps | Yes - browser redirect |
| Client Credentials | Backend services, M2M | No |
| Device Code | TVs, IoT devices | Yes - user enters code |

Neo4j Aura SSO implements **Authorization Code** (with browser redirects). We need **Client Credentials** (no browser). The tokens look similar (both are JWTs) but the backend expects different things.

---

## Summary

| What We Thought | What's Actually True |
|-----------------|---------------------|
| "Bearer token support = SSO support" | Bearer tokens work, but SSO tokens from OAuth need Aura to accept them |
| "SSO enables M2M" | SSO is for humans; M2M needs API keys or accepted service account tokens |
| "We just need to configure Entra correctly" | We configured it correctly; Aura doesn't accept M2M tokens |
| "Other databases use OAuth for M2M" | Most use simple API keys; some use service accounts with OAuth behind the scenes |

---

## Recommendations

1. **Short term**: Use username/password authentication for the MCP server. Store credentials securely (Azure Key Vault, etc.).

2. **Medium term**: Request Neo4j Aura add API key support for database access. This is what every other cloud database offers.

3. **Alternative**: If M2M with OAuth is required, deploy self-hosted Neo4j Enterprise where `dbms.security.oidc.m2m.*` can be configured.

---

## The Enterprise Agent Platform Use Case

The goal is to integrate a hosted Neo4j Aura MCP Server with enterprise agent platforms:
- **Microsoft Azure AI Foundry**
- **Databricks Agent Bricks**
- **AWS Bedrock AgentCore**

Here's how each platform handles MCP server authentication - and why SSO doesn't fit.

### Microsoft Azure AI Foundry

Microsoft Foundry supports these authentication methods for MCP servers:

| Method | Description | Human Required? |
|--------|-------------|-----------------|
| **API Key** | Simple key-based auth | No |
| **Managed Identity** | Azure's service identity | No |
| **Service Principal** | Azure's service accounts | No |
| **OAuth (On-Behalf-Of)** | User identity passthrough | Yes (initial login) |

For "shared authentication" (where every agent interaction uses the same identity), Microsoft explicitly supports **key-based, Managed Identity, or Service Principal** - all M2M patterns.

Reference: [MCP Server Authentication - Microsoft Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/mcp-authentication)

### Databricks Agent Bricks

Databricks MCP servers support:

| Method | Description | Human Required? |
|--------|-------------|-----------------|
| **OAuth Client Credentials** | client_id + client_secret | No |
| **Personal Access Tokens** | For development/testing | No |
| **Unity Catalog Connections** | Managed auth with token refresh | No |

Databricks explicitly states: "MCP servers are secure by default and require clients to specify authentication." They provide a `databricks-mcp` library that handles OAuth client credentials flow automatically.

Reference: [Databricks MCP Authentication](https://docs.databricks.com/aws/en/generative-ai/mcp/connect-external-services)

### AWS Bedrock AgentCore

AWS Bedrock supports:

| Method | Description | Human Required? |
|--------|-------------|-----------------|
| **SigV4** | AWS signature-based auth | No |
| **JWT** | Token-based with IAM | No |
| **OAuth (Service)** | Client credentials flow | No |

AWS documentation explicitly calls out the problem with user-based auth for agents:

> "While user-based authentication works perfectly for direct MCP server testing, this approach has limitations for production agent-to-MCP communication... user authentication is designed for humans, not services."

Reference: [MCP Authentication for Agent Connections in Amazon Bedrock AgentCore](https://www.tecracer.com/blog/2025/10/mcp-authentication-for-agent-connections-in-amazon-bedrock-agentcore.html)

### The Pattern Is Clear

All three platforms support:
1. **Service identities** (managed identity, service principal, IAM roles)
2. **API keys / access tokens** (PATs, API keys)
3. **OAuth Client Credentials** (client_id + client_secret exchanged for tokens)

None of them rely on browser-based SSO for agent-to-MCP communication because **there's no human to click through a login flow**.

---

## The Use Case Mismatch

Here's the flow Neo4j Aura SSO was designed for:

```
Human User → Browser → Neo4j Login Page → Redirect to IdP → Human enters password → Token → Neo4j
```

Here's what enterprise agent platforms need:

```
Agent Platform → MCP Server → Neo4j Aura
     │                │
     │                └── Needs: API key, service credential, or accepted M2M token
     │
     └── Has: Managed Identity, Service Principal, IAM Role, API Key
```

The agent platforms have service credentials. They can pass those to the MCP server. But then the MCP server needs to authenticate to Neo4j Aura - and Aura only accepts:
1. Username/password (works but credentials must be managed)
2. SSO tokens from browser flows (doesn't work for M2M)

**The gap is on the Neo4j Aura side**, not the agent platform side.

---

## What Would Make This Work

For the hosted Neo4j Aura MCP Server to integrate with enterprise agent platforms, Neo4j Aura needs to accept one of:

### Option A: API Keys (Simplest)
```
Agent Platform → MCP Server → Neo4j Aura
                    │
                    └── Authorization: X-API-Key: aura_abc123...
```
Aura validates the API key, grants appropriate database access.

### Option B: Service Account Client Credentials
```
Agent Platform → MCP Server → Aura Token Endpoint → Neo4j Aura
                    │              │
                    │              └── Returns Aura-issued token
                    │
                    └── client_id + client_secret
```
MCP server exchanges service account credentials for an Aura-issued token that Aura actually accepts.

### Option C: Accept External M2M Tokens
```
Agent Platform → MCP Server → IdP Token Endpoint → Neo4j Aura
                    │              │
                    │              └── Returns M2M token
                    │
                    └── client_id + client_secret
```
Aura is configured to accept M2M tokens from external IdPs (Entra, Okta) - like self-hosted Neo4j Enterprise already does.

---

## What Doesn't Work

Trying to use **SSO** (browser-based, human-initiated authentication) for agent platforms:

```
Agent Platform → MCP Server → ??? Browser popup ??? → Human logs in → Token
```

There's no human. There's no browser. The agent runs autonomously. SSO is fundamentally incompatible with this use case.

---

## References

- [Neo4j Aura SSO Documentation](https://neo4j.com/docs/aura/security/single-sign-on/) - User SSO for Aura
- [Neo4j Aura API Authentication](https://neo4j.com/docs/aura/classic/platform/api/authentication/) - For Aura Console API, not database access
- [Supabase API Keys](https://supabase.com/docs/guides/api/api-keys) - Example of simple API key approach
- [MongoDB Atlas API Authentication](https://www.mongodb.com/docs/atlas/api/api-authentication/) - Service accounts for M2M
- [MCP Authorization Tutorial](https://modelcontextprotocol.io/docs/tutorials/security/authorization) - OAuth vs environment credentials
- [MotherDuck MCP Blog](https://motherduck.com/blog/dev-diary-building-mcp/) - OAuth implementation for MCP
- [Migrating from API Keys to OAuth](https://www.scalekit.com/blog/migrating-from-api-keys-to-oauth-mcp-servers) - Discussion of API keys vs OAuth for MCP
- [MCP Server Authentication - Microsoft Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/mcp-authentication) - Azure AI Foundry MCP auth options
- [Databricks MCP Authentication](https://docs.databricks.com/aws/en/generative-ai/mcp/connect-external-services) - Databricks MCP auth
- [MCP Authentication for Agent Connections in Amazon Bedrock AgentCore](https://www.tecracer.com/blog/2025/10/mcp-authentication-for-agent-connections-in-amazon-bedrock-agentcore.html) - AWS Bedrock MCP auth
