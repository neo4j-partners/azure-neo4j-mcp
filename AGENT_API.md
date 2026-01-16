# Proposal: Switch to Neo4j Aura Agent API Authentication

## The Problem

The current approach tries to authenticate to Neo4j Aura using Azure Entra ID (formerly Azure AD) single sign-on. This requires a complex chain of configuration:

1. Create an Azure Entra app registration with specific redirect URIs
2. Configure the app to expose an API with application ID URIs
3. Set up Cognito or Entra as the identity provider in Neo4j Aura
4. Exchange tokens between Azure and Neo4j
5. Map roles and claims between systems
6. Handle both user-based authentication (ROPC flow) and machine-to-machine authentication (client credentials flow)

This approach has several fundamental issues:

- Neo4j Aura SSO was designed for interactive user login, not programmatic machine-to-machine access
- The token exchange between identity providers introduces complexity and failure points
- Client credentials flow tokens from Azure Entra are rejected by Neo4j Aura because they lack the user context that SSO expects
- Testing requires creating Azure AD users without MFA, which is a security concern
- The configuration spans multiple systems (Azure Portal, Neo4j Aura Console, local environment files) making it difficult to troubleshoot

## The Proposed Solution

Abandon the Azure Entra SSO integration entirely and use the Neo4j Aura Agent API instead.

Neo4j provides a dedicated API for programmatic agent access. This API uses a straightforward OAuth client credentials flow where the credentials come directly from your Neo4j user profile, not from a third-party identity provider.

### How the Aura Agent API Works

1. You obtain a client ID and client secret from your Neo4j user profile in the Aura console
2. You post these credentials to the Neo4j OAuth endpoint to get a short-lived bearer token
3. You use that bearer token to call your agent endpoint
4. Tokens are intentionally short-lived for security, requiring fresh authentication for each session

This is fundamentally simpler because:

- All credentials come from Neo4j directly, no third-party identity provider involved
- The OAuth flow is the standard client credentials grant, widely understood and well-supported
- No role mapping or claim translation between systems
- No user accounts needed for programmatic access
- The token endpoint and agent endpoint are both under Neo4j's control

### What This Means for Authentication

The current architecture has the MCP server connecting to Neo4j Aura using a bearer token obtained from Azure Entra. The new architecture would have the MCP server connecting to Neo4j Aura using a bearer token obtained from Neo4j's own OAuth endpoint.

This is not a workaround or a hack. This is the officially documented approach for programmatic agent access to Neo4j Aura.

## Migration Plan

### Remove Current SSO Infrastructure

Delete the following files and components:

- The entire test-sso directory (test_sso.py, test_m2m.py, validate_entra_m2m.py, debug_token.py)
- The app-registration.bicep infrastructure
- The entra-app-registration.bicep module
- The create-user.sh script for creating Azure AD test users
- All Azure Entra configuration from environment files

Remove from the README:

- The Neo4j Aura SSO section
- The SSO testing commands table
- References to APP_REGISTRATION.json

### Build New Token Service

Create a new authentication module that:

- Stores the Neo4j client ID and client secret in Azure Key Vault
- Requests bearer tokens from the Neo4j OAuth endpoint before each operation
- Handles token expiration gracefully by requesting new tokens as needed
- Provides clear error messages when credentials are invalid or expired

### Update Test Infrastructure

Replace the current SSO test scripts with a single test script that:

- Reads Neo4j credentials from environment
- Requests a token from the Neo4j OAuth endpoint
- Calls the agent endpoint with the bearer token
- Validates the response

This should be a straightforward script that demonstrates the authentication flow in isolation before integrating it into the MCP server.

### Update MCP Server Connection

Modify the MCP server to:

- Read Neo4j OAuth credentials from Key Vault instead of Azure Entra configuration
- Request bearer tokens from Neo4j's OAuth endpoint
- Use those tokens for API calls to the agent endpoint

### Update Deployment Scripts

Modify the deployment scripts to:

- Remove the app-registration deployment step
- Add prompts for Neo4j client ID and client secret during setup
- Store Neo4j OAuth credentials in Key Vault
- Remove generation of APP_REGISTRATION.json

### Update Documentation

Rewrite the authentication sections of the README to explain:

- How to obtain Neo4j OAuth credentials from the Aura console
- How those credentials are stored and used
- How to test the authentication flow

## No Backwards Compatibility

This proposal explicitly does not provide backwards compatibility with the Azure Entra SSO approach. The current approach will be completely removed, not deprecated.

Reasons for a clean break:

1. The Azure Entra SSO approach does not work reliably for machine-to-machine access, so there is nothing to preserve
2. Maintaining two authentication paths would complicate the codebase and documentation
3. Anyone currently using the Azure Entra approach is likely experiencing the same issues that prompted this change
4. The new approach is simpler and should be straightforward to adopt

## Expected Outcomes

After this migration:

- Authentication will work reliably for programmatic agent access
- The configuration surface will be significantly smaller (Neo4j credentials only)
- Testing will be simpler (no Azure AD users needed)
- Troubleshooting will be easier (single system involved)
- The codebase will be smaller and easier to maintain

## Reference

This proposal is based on the Neo4j Aura Agent API documentation:
https://neo4j.com/developer/genai-ecosystem/aura-agent/#_api_usage

The documentation describes using OAuth client credentials flow with credentials from your Neo4j user profile, which is exactly what this proposal recommends adopting.
