# Bearer Token Authentication Proposal V2

## Implementation Status

| Phase | Description | Status | Date |
|-------|-------------|--------|------|
| 1 | Reorganize Existing Code | Complete | 2025-01-21 |
| 2 | Design Bearer Architecture | Complete | 2025-01-21 |
| 3 | Create Bearer Infrastructure | Complete | 2025-01-21 |
| 4 | Create Bearer Deployment Script | Complete | 2025-01-21 |
| 5 | Documentation and Samples | Complete | 2025-01-21 |
| 6 | Testing and Validation | Not Started | - |
| 7 | Update Root Documentation | Not Started | - |

---

## Overview

This proposal recommends splitting the project into two independent implementations rather than adding complexity to a single codebase. Each implementation serves a distinct use case and can evolve independently.

---

## Project Structure

### Current State (After Phase 1)

The project is now split into two separate directories:

**simple-mcp-server**
- Contains all existing infrastructure, scripts, and samples
- Uses the Nginx authentication proxy with static API keys
- Best for quick demos, development environments, and scenarios where SSO is not required
- Simple to deploy and understand

**bearer-mcp-server**
- New implementation built specifically for bearer token authentication
- No Nginx proxy - the MCP server handles authentication directly
- Designed for enterprise environments with identity provider integration
- Supports SSO, OIDC, and user-level audit trails

---

## Why Split Instead of Add a Flag

### Simplicity Over Flexibility

Adding a `--bearer` flag to the existing deployment would create conditional logic throughout the codebase. Every Bicep template, every script function, and every configuration file would need to handle two different modes. This leads to:

- More complex code that is harder to maintain
- More testing scenarios to cover
- Higher risk of bugs when changes affect one mode but not the other
- Confusing documentation that must explain both paths

### Clear Purpose for Each Implementation

By splitting the project, each implementation has a single clear purpose:

**simple-mcp-server** answers: "How do I quickly deploy an MCP server to Azure with basic security?"

**bearer-mcp-server** answers: "How do I deploy an MCP server that integrates with my enterprise identity provider?"

### Independent Evolution

The two implementations can evolve at different speeds based on their target audiences:

- Simple version can stay stable and straightforward
- Bearer version can add enterprise features without complicating the simple case
- Bug fixes in one do not risk breaking the other

---

## What Goes Where

### simple-mcp-server

Move all existing content into this directory:

- The deploy script and all helper scripts
- The Nginx authentication proxy configuration and Dockerfile
- All Bicep infrastructure templates
- The test client and samples
- Environment setup scripts
- Current documentation

This directory becomes a self-contained, working deployment that matches what exists today. No functionality changes, just reorganization.

### bearer-mcp-server

Create this as a fresh implementation with:

- A new deploy script designed from the ground up for bearer authentication
- Simplified Bicep templates for single-container deployment
- No Nginx proxy code at all
- Documentation focused on identity provider setup
- Sample client code showing token acquisition and usage

---

## Benefits of Bearer Token Authentication

### For Security Teams

Identity provider integration means authentication follows your existing enterprise policies. Users authenticate the same way they access other corporate resources. Multi-factor authentication, conditional access policies, and session management all apply automatically.

### For Compliance

Every query to Neo4j carries the identity of the caller. Audit logs show which user ran which query, not just that "someone with the API key" made a request. This satisfies regulatory requirements around access tracking and accountability.

### For Operations

One container instead of two means simpler deployments, fewer moving parts, and reduced resource consumption. No custom Lua code to maintain in the Nginx proxy. Standard OAuth flows that security teams already understand.

### For Developers

Clients obtain tokens from the identity provider using standard libraries available in every language. No need to manage or rotate API keys. Token expiration is automatic - no risk of using stale credentials.

---

## Phased Implementation Plan

### Phase 1: Reorganize Existing Code

**Status**: Complete (2025-01-21)

**Goal**: Move existing code to simple-mcp-server without breaking anything

**Activities**:
- Create the simple-mcp-server directory
- Move all existing files into this directory
- Update any hardcoded paths in scripts
- Update the root README to explain the new structure
- Test that deployment still works from the new location

**Outcome**: The project has a new structure but all functionality remains identical

**Duration**: Short - this is purely file reorganization

**Completion Notes**:

The following changes were made:

1. Created `simple-mcp-server/` directory and moved:
   - `scripts/` - all deployment and setup scripts
   - `infra/` - all Bicep infrastructure templates
   - `client/` - test client code
   - `docs/` - architecture documentation
   - `samples/` - agent samples and integrations
   - `databrick_samples/` - Databricks notebook examples
   - `.env.sample` - environment template
   - `README.md` - full documentation (now at simple-mcp-server/README.md)

2. Created `bearer-mcp-server/` directory with placeholder README

3. Created new root `README.md` with:
   - Decision guide for choosing between implementations
   - Project structure overview
   - Quick start instructions for each approach

4. Verified deployment scripts work from new location:
   - Scripts use relative paths based on their own location
   - Bicep lint passes from new directory
   - No hardcoded paths needed updating

**New Project Structure**:
```
azure-neo4j-mcp/
├── simple-mcp-server/      # API key authentication (production ready)
│   ├── scripts/
│   ├── infra/
│   ├── client/
│   ├── samples/
│   ├── databrick_samples/
│   ├── docs/
│   ├── .env.sample
│   └── README.md
├── bearer-mcp-server/      # Bearer token authentication (planned)
│   └── README.md
├── BEARER_AUTH_V2.md
├── BEARER_AUTH.md
└── README.md
```

**To Deploy from New Location**:
```bash
cd simple-mcp-server
cp .env.sample .env
# Edit .env with your credentials
./scripts/deploy.sh
```

---

### Phase 2: Design Bearer Architecture

**Status**: Complete (2025-01-21)

**Goal**: Document the technical design for bearer-mcp-server before writing code

**Activities**:
- Define the target architecture for single-container deployment
- Document which Azure resources are needed and which can be removed
- Specify how the Container App will be configured for direct MCP server access
- Determine what secrets still need Key Vault storage
- Plan the health check and monitoring approach without Nginx
- Identify which identity providers to support initially

**Outcome**: A clear technical specification that guides implementation

**Duration**: Medium - requires careful thought about enterprise requirements

**Completion Notes**:

Research conducted on latest best practices:
- Azure Container Apps API version 2025-01-01 for container apps
- Azure Key Vault API version 2025-05-01 with RBAC authorization
- Log Analytics API version 2025-07-01
- Container Registry API version 2025-11-01
- MCP Streamable HTTP transport specification (2025-03-26)

Architecture decisions:
1. **Single Container**: MCP server only (no Nginx proxy)
2. **External Ingress**: Direct to port 8000 (MCP server HTTP port)
3. **No Static Credentials**: Key Vault stores only connection info (URI, database name)
4. **Per-Request Auth**: Bearer tokens extracted from Authorization header, passed to Neo4j
5. **TCP Health Probes**: MCP server lacks dedicated health endpoint, use TCP socket checks
6. **CORS Support**: Configurable via environment variable for web-based clients

Key differences from simple-mcp-server:
| Aspect | simple-mcp-server | bearer-mcp-server |
|--------|-------------------|-------------------|
| Containers | 2 (Nginx + MCP) | 1 (MCP only) |
| CPU | 0.75 vCPU | 0.5 vCPU |
| Memory | 1.5 GiB | 1.0 GiB |
| Key Vault Secrets | 5 | 2 |
| Authentication | Static API key | JWT bearer tokens |

Supported identity providers:
- Microsoft Entra ID (primary documentation target)
- Okta
- Auth0
- Keycloak
- AWS Cognito

---

### Phase 3: Create Bearer Infrastructure

**Status**: Complete (2025-01-21)

**Goal**: Build the Bicep templates for bearer-mcp-server

**Activities**:
- Create new Bicep templates from scratch, not by modifying existing ones
- Design for single container deployment with external ingress
- Configure environment variables for HTTP transport mode without static credentials
- Set up Key Vault for only the secrets that bearer mode requires
- Implement health checks that work without the Nginx proxy
- Add appropriate CORS configuration for web-based clients

**Outcome**: Infrastructure as code ready for bearer authentication deployments

**Duration**: Medium - straightforward once design is complete

**Completion Notes**:

Created the following Bicep templates in `bearer-mcp-server/infra/`:

**Main Template** (`main.bicep`):
- Orchestrates all module deployments
- Accepts minimal parameters (no credentials)
- Outputs MCP endpoint URL for client configuration

**Modules Created**:
1. `modules/container-app.bicep` - Single-container MCP server with:
   - External ingress on port 8000
   - HTTP transport mode configuration
   - Bearer token pass-through (no credential injection)
   - TCP health probes (liveness, readiness, startup)
   - CORS policy configuration
   - Read-only mode option

2. `modules/key-vault.bicep` - Minimal secrets storage:
   - Only stores neo4j-uri and neo4j-database
   - No credentials (username, password, API key)
   - RBAC authorization enabled

3. `modules/container-environment.bicep` - Standard configuration:
   - Consumption workload profile
   - Log Analytics integration

4. `modules/container-registry.bicep` - Image storage:
   - AcrPull role for managed identity

5. `modules/log-analytics.bicep` - Telemetry:
   - PerGB2018 SKU, 30-day retention

6. `modules/managed-identity.bicep` - Authentication:
   - Used for ACR pull only (no Key Vault access needed at runtime)

**Parameter File** (`main.bicepparam`):
- Uses `readEnvironmentVariable()` for configuration
- Required: NEO4J_URI
- Optional: NEO4J_DATABASE, BASE_NAME, ENVIRONMENT, etc.

**Validation**:
- Bicep lint passes with no errors
- All API versions are latest stable (2025)

**File Structure**:
```
bearer-mcp-server/
├── infra/
│   ├── main.bicep
│   ├── main.bicepparam
│   ├── bicepconfig.json
│   └── modules/
│       ├── container-app.bicep
│       ├── container-environment.bicep
│       ├── container-registry.bicep
│       ├── key-vault.bicep
│       ├── log-analytics.bicep
│       └── managed-identity.bicep
└── README.md
```

---

### Phase 4: Create Bearer Deployment Script

**Status**: Complete (2025-01-21)

**Goal**: Build the deployment automation for bearer-mcp-server

**Activities**:
- Write a new deploy script specific to bearer authentication
- Include validation that the target Neo4j instance supports OIDC
- Generate output files with identity provider configuration guidance
- Add commands for common operations like viewing logs and checking status
- Document prerequisites clearly, especially Neo4j Enterprise requirements

**Outcome**: Complete deployment automation for bearer mode

**Duration**: Medium - similar complexity to existing script but simpler logic

**Completion Notes**:

Created deployment script at `bearer-mcp-server/scripts/deploy.sh` with:

**Commands**:
- `deploy` - Full deployment (default)
- `redeploy` - Rebuild and update container
- `lint` - Validate Bicep templates
- `status` - Show deployment status
- `logs [N]` - Show last N container logs

**Features**:
- Simplified single-container deployment (no Nginx proxy)
- No static credentials stored or validated
- Warning about Neo4j OIDC requirements
- Generates `MCP_ACCESS.json` with bearer auth configuration
- Includes identity provider token endpoint examples

**Environment Template** (`.env.sample`):
- Required: AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, AZURE_LOCATION, NEO4J_URI
- Optional: NEO4J_DATABASE, BASE_NAME, ENVIRONMENT, NEO4J_READ_ONLY, CORS_ALLOWED_ORIGINS
- Reference section for IdP configuration (not used by script)

**API Version Update**:
During review, updated to latest stable API versions:
- Container Apps: 2025-07-01 (was 2025-01-01)
- Managed Environments: 2025-07-01 (was 2025-01-01)

---

### Phase 5: Documentation and Samples

**Status**: Complete (2025-01-21)

**Goal**: Make bearer-mcp-server easy to adopt

**Activities**:
- Write a comprehensive README explaining when to use bearer authentication
- Document identity provider setup for Microsoft Entra ID as the primary example
- Provide guidance for other providers like Okta and Auth0
- Create sample client code showing token acquisition
- Include troubleshooting guidance for common authentication issues
- Document the Neo4j OIDC configuration requirements

**Outcome**: Users can successfully deploy and integrate with their identity provider

**Duration**: Medium to Long - good documentation takes time

**Completion Notes**:

Created comprehensive documentation in `bearer-mcp-server/docs/`:

**IDENTITY_PROVIDER_SETUP.md**:
- Step-by-step guides for Microsoft Entra ID, Okta, Auth0, and Keycloak
- Neo4j OIDC configuration examples for each provider
- Token acquisition code samples (Python, Azure CLI, curl)
- Group-to-role mapping configuration
- Security best practices

**TROUBLESHOOTING.md**:
- Quick diagnostic checklist
- Authentication error resolution (401, 403 errors)
- Token validation debugging
- Neo4j connection troubleshooting
- Container App issues (restarts, health probes, image pull)
- JWT decoding and debugging commands
- Common misconfigurations

**Test Client** (`bearer-mcp-server/client/test_bearer_client.py`):
- Python client with Azure Entra ID token acquisition
- Supports direct token or Azure credentials
- Test suite: initialize, list_tools, get_schema, read_cypher
- Environment variable configuration
- Loads endpoint from MCP_ACCESS.json

**Updated README**:
- Quick start guide
- Complete project structure
- Reflects Phase 2-5 completion

**File Structure**:
```
bearer-mcp-server/
├── scripts/
│   └── deploy.sh
├── client/
│   ├── test_bearer_client.py
│   └── requirements.txt
├── docs/
│   ├── IDENTITY_PROVIDER_SETUP.md
│   └── TROUBLESHOOTING.md
├── infra/
│   └── ... (from Phase 3)
├── .env.sample
└── README.md
```

---

### Phase 6: Testing and Validation

**Goal**: Ensure bearer-mcp-server works reliably in real environments

**Activities**:
- Test with Microsoft Entra ID in a real Azure tenant
- Test with at least one other identity provider
- Verify token expiration and refresh scenarios work correctly
- Confirm audit logging shows user identity in Neo4j
- Test error scenarios like expired tokens and revoked access
- Validate that health checks work for container orchestration

**Outcome**: Confidence that the implementation works in production scenarios

**Duration**: Medium - depends on access to test environments

---

### Phase 7: Update Root Documentation

**Goal**: Help users choose the right implementation

**Activities**:
- Update the root README to explain both options clearly
- Create a decision guide helping users pick simple vs bearer
- Link to the appropriate subdirectory based on use case
- Archive or remove the original BEARER_AUTH.md proposal

**Outcome**: Clear entry point for new users regardless of their requirements

**Duration**: Short - straightforward documentation update

---

## Prerequisites for Bearer Mode

### Neo4j Requirements

Bearer token authentication requires the Neo4j instance to validate JWT tokens. This capability exists in:

- Neo4j Enterprise Edition (self-hosted) with OIDC configured
- Potentially Neo4j Aura Enterprise with SSO enabled (requires verification with Neo4j)

Neo4j Community Edition and standard Aura tiers do not support OIDC authentication at the driver level.

### Identity Provider Requirements

Any OIDC-compliant identity provider works. The documentation will focus on Microsoft Entra ID since it integrates naturally with Azure deployments, but the implementation will work with Okta, Auth0, Keycloak, and others.

### Client Requirements

Clients need the ability to obtain OAuth tokens from the identity provider. For machine-to-machine scenarios, this means having a registered application with client credentials. For user-delegation scenarios, this means implementing an OAuth flow appropriate to the client type.

---

## What This Proposal Does Not Cover

### Hybrid Authentication

This proposal does not attempt to support both API key and bearer token authentication in the same deployment. Users choose one approach based on their requirements.

### Token Issuance

The MCP server does not issue tokens. Clients obtain tokens from their identity provider before making requests. The MCP server simply passes tokens through to Neo4j.

### Identity Provider Setup

While documentation will guide users through identity provider configuration, the deployment scripts do not automate IdP setup. Organizations have different policies and existing configurations that make automation impractical.

### Neo4j OIDC Configuration

The deployment assumes the target Neo4j instance is already configured for OIDC. Instructions for Neo4j configuration will be provided but this is outside the scope of the Azure deployment automation.

---

## Success Criteria

### For Phase 1 (Reorganization)

- Existing deployment works identically from new location
- No broken links or references in documentation
- Clear structure visible in repository root

### For Complete Implementation

- A new user can deploy bearer-mcp-server and authenticate with Microsoft Entra ID within one hour, assuming they have appropriate Azure and Neo4j access
- Query audit logs in Neo4j show the identity of the calling user
- Token expiration results in clear error messages, not mysterious failures
- Documentation answers common questions without requiring support

---

## Recommendation

Proceed with this phased approach. The reorganization in Phase 1 provides immediate clarity about project structure with minimal risk. Subsequent phases can proceed at whatever pace makes sense based on demand for enterprise authentication features.

The split approach keeps both implementations clean and focused. Users with simple requirements get a simple solution. Users with enterprise requirements get an implementation designed for their needs from the start.
