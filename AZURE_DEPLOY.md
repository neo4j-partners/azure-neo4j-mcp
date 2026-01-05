# Neo4j MCP Server - Azure Container Apps Deployment Proposal

## Executive Summary

This proposal outlines the deployment of the official Neo4j MCP (Model Context Protocol) server to Azure Container Apps using Bicep infrastructure-as-code. This is a demo deployment designed for simplicity and quick setup while maintaining security through API key authentication.

---

## Problem Statement

Organizations using Azure want to deploy the Neo4j MCP server to enable AI agents (Claude, Copilot, etc.) to query Neo4j graph databases through the standardized Model Context Protocol. Currently, there is no Azure-native deployment pattern for this server, forcing teams to either:

- Run the MCP server locally, limiting accessibility and requiring manual management
- Use non-Azure cloud providers, complicating infrastructure when Azure is the primary platform
- Build custom deployment solutions without established best practices

---

## Proposed Solution

Deploy the Neo4j MCP server as a containerized application on Azure Container Apps, with:

- **Local Docker image build** following the same pattern as the AWS deployment
- **Azure Container Registry (ACR)** for private image storage with managed identity authentication
- **Azure Key Vault** for secure storage of Neo4j credentials and API key
- **API Key Authentication** using a JWT key from the .env file for simple, secure access
- **Bicep templates** for declarative, repeatable infrastructure deployment
- **Test client** to validate the deployment
- **MCP access info file** generated after deployment for client configuration

---

## Architecture Overview

```
                                    Azure Cloud
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌─────────────┐                 ┌─────────────────────────────┐            │
│  │   AI Agent  │──── API Key ───▶│   Azure Container Apps      │            │
│  │  (Claude)   │     (JWT)       │   Environment               │            │
│  └─────────────┘                 │  ┌───────────────────────┐  │            │
│                                  │  │  Container App        │  │            │
│                                  │  │  (Neo4j MCP Server)   │  │            │
│                                  │  │  Port 8000            │  │            │
│                                  │  │  1 Fixed Instance     │  │            │
│                                  │  └───────────────────────┘  │            │
│                                  └─────────────────────────────┘            │
│                                                   │                          │
│  ┌────────────────────────────────────────────────┼──────────────────────┐  │
│  │  Supporting Services                           │                      │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                   │  │
│  │  │   Azure     │  │   Azure     │  │    Log      │                   │  │
│  │  │ Container   │  │  Key Vault  │  │  Analytics  │                   │  │
│  │  │  Registry   │  │  (Secrets)  │  │ (Telemetry) │                   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                   │                          │
└───────────────────────────────────────────────────┼──────────────────────────┘
                                                    │
                                                    ▼
                                             ┌─────────────┐
                                             │  Neo4j Aura │
                                             │  Database   │
                                             └─────────────┘
```

### Authentication Flow

```
┌───────────┐      ┌───────────────┐      ┌───────────┐      ┌─────────┐
│  AI Agent │──1──▶│ Container App │──2──▶│  MCP Srv  │──3──▶│  Neo4j  │
│           │◀──4──│   Ingress     │      │           │◀──4──│         │
└───────────┘      └───────────────┘      └───────────┘      └─────────┘

1. Agent sends MCP request with API key (JWT) in Authorization header
2. Container App validates API key and forwards to MCP server
3. MCP server executes Cypher query against Neo4j
4. Results flow back through the chain
```

---

## Azure Resources Required

| Resource | Purpose | Azure Service |
|----------|---------|---------------|
| Container Environment | Hosts the container app with networking | Azure Container Apps Environment |
| Container App | Runs the Neo4j MCP server (1 fixed instance) | Azure Container Apps |
| Container Registry | Stores the Docker image privately | Azure Container Registry (Basic SKU) |
| Key Vault | Stores Neo4j credentials and API key | Azure Key Vault |
| Log Analytics Workspace | Collects container logs and metrics | Azure Monitor Log Analytics |
| User-Assigned Managed Identity | Authenticates ACR pulls and Key Vault access | Azure Managed Identity |

---

## Bicep Module Structure

```
infra/
├── main.bicep                    # Entry point, orchestrates all modules
├── main.bicepparam               # Parameter file with deployment values
├── modules/
│   ├── container-registry.bicep  # ACR with managed identity configuration
│   ├── key-vault.bicep           # Key Vault with RBAC and secrets
│   ├── log-analytics.bicep       # Log Analytics workspace
│   ├── managed-identity.bicep    # User-assigned managed identity
│   ├── container-environment.bicep # Container Apps environment
│   └── container-app.bicep       # The Neo4j MCP server container app
├── scripts/
│   └── deploy.sh                 # Deployment script (mirrors AWS pattern)
└── client/
    ├── test_client.py            # Python test client for validation
    └── requirements.txt          # Client dependencies
```

### Module Dependencies

The Bicep modules will be deployed in dependency order:

1. **Managed Identity** - Created first as other resources reference it
2. **Log Analytics Workspace** - Required by Container Apps Environment
3. **Key Vault** - Stores secrets, grants access to Managed Identity
4. **Container Registry** - Stores images, grants AcrPull to Managed Identity
5. **Container Apps Environment** - Requires Log Analytics
6. **Container App** - Requires all above resources, fixed at 1 instance

---

## Container Image Build Strategy

### Local Build Approach

The Docker image will be built locally using the official Neo4j MCP server Dockerfile, then pushed to Azure Container Registry.

**Build Process:**

1. Clone or reference the official Neo4j MCP repository
2. Build the Docker image locally using docker buildx for linux/amd64
3. Authenticate to Azure Container Registry using Azure CLI
4. Tag and push the image to ACR

**Image Tagging:**

- Use "latest" tag for demo simplicity
- Include build timestamp for traceability

---

## Secrets Management

### Key Vault Secrets

| Secret Name | Description | Source |
|-------------|-------------|--------|
| neo4j-uri | Neo4j connection string | .env file |
| neo4j-username | Database username | .env file |
| neo4j-password | Database password | .env file |
| neo4j-database | Database name | .env file |
| mcp-api-key | JWT key for API authentication | .env file |

### Access Pattern

The Container App uses Key Vault references with a user-assigned managed identity granted the "Key Vault Secrets User" RBAC role. This avoids the chicken-and-egg problem of system-assigned identity during initial deployment.

---

## API Key Authentication

### How It Works

The MCP server will validate incoming requests using a JWT key stored in Key Vault. Clients must include this key in the Authorization header of their requests.

**Request Format:**
```
Authorization: Bearer <MCP_API_KEY>
```

**Configuration:**

The API key is defined in the .env file as MCP_API_KEY and stored in Key Vault during deployment. The Container App retrieves it at runtime and validates incoming requests.

### Security Considerations

- The API key should be a strong, randomly generated string (minimum 32 characters)
- Rotate the key periodically by updating Key Vault and redeploying
- Use HTTPS only (enforced by Container Apps ingress)

---

## Ingress Configuration

### External Ingress (Public Access)

- External ingress enabled for demo accessibility
- HTTPS-only traffic (port 443 externally, port 8000 internally)
- Azure provides automatic TLS certificate management
- No custom domain required for demo

### Security

- API key required for all requests
- HTTPS enforced by default
- Container App only accepts validated requests

---

## Fixed Instance Configuration

For demo simplicity, the Container App runs exactly 1 instance:

- **Minimum Replicas:** 1
- **Maximum Replicas:** 1
- **No autoscaling** - consistent behavior for demos

This ensures predictable performance and avoids cold start delays during demonstrations.

---

## Environment Configuration

### .env File Structure

```
# =============================================================================
# Azure Configuration
# =============================================================================
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_RESOURCE_GROUP=neo4j-mcp-demo-rg
AZURE_LOCATION=eastus

# =============================================================================
# Neo4j Database Connection
# =============================================================================
NEO4J_URI=neo4j+s://xxx.databases.neo4j.io
NEO4J_DATABASE=neo4j
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=your-neo4j-password

# =============================================================================
# MCP Server Authentication
# =============================================================================
# JWT key for API authentication (generate a strong random string)
MCP_API_KEY=your-secure-api-key-minimum-32-characters

# =============================================================================
# Optional Configuration
# =============================================================================
# CONTAINER_APP_NAME=neo4j-mcp-server
# ACR_NAME=neo4jmcpacr
```

### .env.sample File

A sample file will be provided with placeholder values and documentation for each variable.

---

## Deployment Script Commands

| Command | Description |
|---------|-------------|
| `./deploy.sh` | Full deployment (build, push, deploy infrastructure) |
| `./deploy.sh build` | Build Docker image locally only |
| `./deploy.sh push` | Push image to ACR only |
| `./deploy.sh infra` | Deploy Bicep infrastructure only |
| `./deploy.sh status` | Show deployment status and outputs |
| `./deploy.sh test` | Run test client to validate deployment |
| `./deploy.sh cleanup` | Delete all Azure resources |
| `./deploy.sh help` | Show usage information |

### Prerequisites

- Azure CLI installed and authenticated
- Docker with buildx support
- Python 3.10+ (for test client)
- Access to target Azure subscription with Contributor role

---

## Test Client

### Purpose

A Python test client validates the deployment by:

1. Reading connection info from the generated MCP access file
2. Authenticating with the API key
3. Calling MCP tools (get-schema, read-cypher)
4. Reporting success or failure

### Test Client Features

- Reads MCP_ACCESS.json for connection details
- Validates API key authentication works
- Tests get-schema tool to retrieve database schema
- Tests read-cypher tool with a simple query
- Outputs detailed results for debugging

### Usage

```bash
# Run after deployment
./deploy.sh test

# Or run directly
cd client
python test_client.py
```

---

## MCP Access Info File

After successful deployment, the script generates an MCP access info file containing all information needed to connect to the deployed server.

### File: MCP_ACCESS.json

```json
{
  "endpoint": "https://neo4j-mcp-server.azurecontainerapps.io",
  "api_key": "<retrieved-from-keyvault-or-env>",
  "transport": "http",
  "port": 443,
  "tools": [
    "get-schema",
    "read-cypher",
    "write-cypher",
    "list-gds-procedures"
  ],
  "example_request": {
    "method": "POST",
    "url": "https://neo4j-mcp-server.azurecontainerapps.io/mcp/v1/tools/call",
    "headers": {
      "Authorization": "Bearer <MCP_API_KEY>",
      "Content-Type": "application/json"
    },
    "body": {
      "name": "get-schema",
      "arguments": {}
    }
  }
}
```

### Claude Desktop Configuration

The file also includes configuration for Claude Desktop:

```json
{
  "claude_desktop_config": {
    "mcpServers": {
      "neo4j": {
        "command": "curl",
        "args": [
          "-X", "POST",
          "-H", "Authorization: Bearer <MCP_API_KEY>",
          "-H", "Content-Type: application/json",
          "https://neo4j-mcp-server.azurecontainerapps.io"
        ]
      }
    }
  }
}
```

---

## Comparison with AWS Deployment

| Aspect | AWS Deployment | Azure Deployment (Demo) |
|--------|----------------|------------------------|
| Container Platform | Bedrock AgentCore Runtime | Azure Container Apps |
| Container Registry | Amazon ECR | Azure Container Registry |
| Secrets Management | AWS Secrets Manager | Azure Key Vault |
| Authentication | Cognito OAuth2 M2M | API Key (JWT) |
| Scaling | Auto-scaling | Fixed 1 instance |
| Infrastructure-as-Code | AWS CDK (Python) | Bicep |
| Complexity | Production-ready | Demo-focused |

---

## Implementation Status

### Bicep API Versions Used

The following API versions are used based on latest best practices (January 2025):

| Resource | API Version | Reference |
|----------|-------------|-----------|
| Managed Identity | `2024-11-30` | [Microsoft.ManagedIdentity](https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/userassignedidentities) |
| Log Analytics | `2025-02-01` | [Microsoft.OperationalInsights](https://learn.microsoft.com/en-us/azure/templates/microsoft.operationalinsights/workspaces) |
| Container Registry | `2025-04-01` | [Microsoft.ContainerRegistry](https://learn.microsoft.com/en-us/azure/templates/microsoft.containerregistry/registries) |
| Role Assignments | `2022-04-01` | [Microsoft.Authorization](https://learn.microsoft.com/en-us/azure/templates/microsoft.authorization/roleassignments) |
| Key Vault | `2024-04-01-preview` | [Microsoft.KeyVault](https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults) |
| Container Apps Environment | `2024-03-01` | [Microsoft.App/managedEnvironments](https://learn.microsoft.com/en-us/azure/templates/microsoft.app/managedenvironments) |
| Container App | `2024-03-01` | [Microsoft.App/containerApps](https://learn.microsoft.com/en-us/azure/templates/microsoft.app/containerapps) |

---

## Implementation Requirements

### Phase 1: Foundation - COMPLETED

| Task | Status | File |
|------|--------|------|
| Create Bicep module for user-assigned managed identity | Done | `infra/modules/managed-identity.bicep` |
| Create Bicep module for Log Analytics Workspace with 30-day retention | Done | `infra/modules/log-analytics.bicep` |
| Create Bicep module for Azure Container Registry with Basic SKU | Done | `infra/modules/container-registry.bicep` |
| Configure RBAC role assignment granting managed identity AcrPull permission | Done | Included in `container-registry.bicep` |
| Create main.bicep entry point | Done | `infra/main.bicep` |
| Create parameter file | Done | `infra/main.bicepparam` |

**Files Created:**
```
infra/
├── main.bicep                    # Entry point, orchestrates all modules
├── main.bicepparam               # Parameter file with deployment values
└── modules/
    ├── managed-identity.bicep    # User-assigned managed identity
    ├── log-analytics.bicep       # Log Analytics workspace
    └── container-registry.bicep  # ACR with AcrPull role assignment
```

**Key Implementation Details:**

- **Managed Identity**: Uses `principalType: 'ServicePrincipal'` for role assignments to avoid intermittent deployment errors
- **Container Registry**: Admin user disabled for security, uses managed identity with AcrPull role
- **Log Analytics**: Configured with 30-day retention for cost optimization
- **Naming**: Uses `uniqueString(resourceGroup().id)` for globally unique ACR names

### Phase 2: Secrets and Security - COMPLETED

| Task | Status | File |
|------|--------|------|
| Create Bicep module for Azure Key Vault with RBAC authorization | Done | `infra/modules/key-vault.bicep` |
| Configure RBAC role assignment granting managed identity Key Vault Secrets User | Done | Included in `key-vault.bicep` |
| Create secrets for Neo4j connection parameters and MCP API key | Done | Included in `key-vault.bicep` |

**Key Implementation Details:**

- **RBAC Authorization**: Enabled by default, no access policies needed
- **Soft Delete**: Enabled with 7-day retention (minimum for demo cleanup)
- **Purge Protection**: Disabled to allow full cleanup during development
- **Secrets Created**: `neo4j-uri`, `neo4j-username`, `neo4j-password`, `neo4j-database`, `mcp-api-key`
- **Naming**: Uses `kv${uniqueString(resourceGroup().id)}` to stay within 24-character limit

### Phase 3: Container Environment - COMPLETED

| Task | Status | File |
|------|--------|------|
| Create Bicep module for Container Apps Environment linked to Log Analytics | Done | `infra/modules/container-environment.bicep` |
| Configure environment for consumption-based workload profile | Done | Default Consumption profile |
| Zone redundancy disabled for cost optimization | Done | For demo simplicity |

**Key Implementation Details:**

- **Workload Profile**: Consumption (serverless, pay-per-use)
- **Log Analytics Integration**: Configured via shared key authentication
- **Zone Redundancy**: Disabled for demo (reduces cost and complexity)

### Phase 4: Container App - COMPLETED

| Task | Status | File |
|------|--------|------|
| Create Bicep module for Container App with fixed 1 replica | Done | `infra/modules/container-app.bicep` |
| Configure managed identity for image pull authentication | Done | User-assigned identity for ACR |
| Configure Key Vault references for all environment variables | Done | All secrets from Key Vault |
| Set container resource limits (CPU: 0.5, Memory: 1Gi) | Done | Consumption tier limits |
| Configure HTTP ingress on port 8000 with external access | Done | HTTPS-only external ingress |
| Configure health probes | Done | TCP liveness/readiness probes |

**Key Implementation Details:**

- **Scale**: Fixed at exactly 1 replica (minReplicas: 1, maxReplicas: 1)
- **Identity**: User-assigned managed identity for both ACR pull and Key Vault access
- **Secrets**: All sensitive values retrieved from Key Vault at runtime
- **Environment Variables**:
  - `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`, `NEO4J_DATABASE` (from Key Vault)
  - `MCP_API_KEY` (from Key Vault)
  - `MCP_TRANSPORT=streamable-http`, `MCP_PORT=8000` (hardcoded)
- **Health Probes**: TCP-based probes (update to HTTP if MCP server exposes health endpoint)
- **Ingress**: External HTTPS on port 443, targeting container port 8000

**Files Created (Phases 2-4):**
```
infra/
├── main.bicep                    # Updated with all phases
├── main.bicepparam               # Updated with secure parameter documentation
└── modules/
    ├── key-vault.bicep           # Key Vault with secrets
    ├── container-environment.bicep # Container Apps Environment
    └── container-app.bicep       # Neo4j MCP Server Container App
```

### Phase 5: Deployment Automation

1. Create deploy.sh script with all commands (build, push, infra, status, test, cleanup, help)
2. Implement local Docker build using docker buildx for linux/amd64
3. Implement ACR authentication and image push
4. Implement Bicep deployment using az deployment group create
5. Implement MCP_ACCESS.json generation after successful deployment
6. Create .env.sample file documenting all configuration variables

### Phase 6: Test Client

1. Create Python test client that reads MCP_ACCESS.json
2. Implement API key authentication in client
3. Implement get-schema tool call test
4. Implement read-cypher tool call test with simple query
5. Add clear success/failure output with debugging information
6. Integrate test command into deploy.sh

---

## Verification Checklist

Before considering deployment complete, verify:

- [ ] All Bicep modules deploy without errors
- [ ] Container App pulls image from ACR using managed identity
- [ ] Container App retrieves secrets from Key Vault using managed identity
- [ ] MCP server responds to health check requests
- [ ] API key authentication rejects requests without valid key
- [ ] API key authentication accepts requests with valid key
- [ ] MCP server successfully connects to Neo4j database
- [ ] get-schema tool returns database schema
- [ ] read-cypher tool executes queries successfully
- [ ] MCP_ACCESS.json is generated with correct endpoint and configuration
- [ ] Test client passes all validation checks
- [ ] Logs appear in Log Analytics Workspace
- [ ] Cleanup command removes all resources completely

---

## Cost Estimate (Demo)

| Resource | Estimated Monthly Cost | Notes |
|----------|----------------------|-------|
| Container Apps (1 instance) | ~$15-30 | Always running |
| Container Registry (Basic) | $5 | 10 GB storage included |
| Key Vault | ~$0.50 | Minimal operations |
| Log Analytics | ~$2-5 | Low log volume |
| **Total** | **~$25-40/month** | Demo usage |

---

## Next Steps

1. Review and approve this proposal
2. Create Azure resource group in target subscription
3. Configure .env file with Neo4j and Azure credentials
4. Generate a secure MCP_API_KEY (minimum 32 characters)
5. Execute deployment with `./deploy.sh`
6. Validate with `./deploy.sh test`
7. Use MCP_ACCESS.json to configure AI agent clients

---

## Open Questions - User Input Required

The following questions arose during implementation. Please provide answers below each question:

### Q1: Neo4j MCP Server Environment Variables

The current implementation assumes the Neo4j MCP server uses these environment variables:
- `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`, `NEO4J_DATABASE`
- `MCP_API_KEY` for authentication
- `MCP_TRANSPORT=streamable-http` and `MCP_PORT=8000`

**Question**: Are these the correct environment variable names for the official Neo4j MCP server? If not, what are the correct names?

**Your Answer**: Yes, these are correct. Updated implementation to use consistent naming.

**Research Findings**: The environment variable names are slightly different:
- `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`, `NEO4J_DATABASE` - Correct
- `NEO4J_MCP_TRANSPORT` (not `MCP_TRANSPORT`) - Transport mode: `stdio` or `http`
- `NEO4J_MCP_HTTP_PORT` (not `MCP_PORT`) - HTTP server port
- `NEO4J_MCP_HTTP_HOST` - HTTP server bind address (default: `127.0.0.1`)

**Additional Answer**:   Use `NEO4J_MCP_TRANSPORT=streamable-http` and `NEO4J_MCP_HTTP_HOST` and `NEO4J_MCP_HTTP_PORT=8000` for correct configuration.

---


### Q2: MCP Server Health Endpoint

Currently using TCP-based health probes on port 8000. If the MCP server exposes an HTTP health endpoint, we can configure more accurate health checks.

**Question**: Does the Neo4j MCP server expose a health check endpoint? If so, what is the path (e.g., `/health`, `/healthz`, `/mcp/health`)?

**Your Answer**: Review the Neo4j MCP server at /Users/ryanknight/projects/mcp to confirm the health endpoint path.

**Research Findings**: The Neo4j MCP server does **NOT** have a dedicated health endpoint. Key findings:
- The server **only responds to `/mcp` path** (enforced by `pathValidationMiddleware`)
- All other paths return 404 with message: "Not Found: This server only handles requests to /mcp"
- For health checks, MCP clients can send `initialize` requests (which don't require auth)
- **Recommendation**: Use TCP probe on port 8000 (current implementation is correct)

**Additional Answer**:  Use Recommendation: Use TCP probe on port 8000 (current implementation is correct)
---

### Q3: API Key Authentication Mechanism

The implementation passes `MCP_API_KEY` as an environment variable. The proposal mentions the Container App validates the API key.

**Question**: How does the Neo4j MCP server validate the API key? Does it:
- (a) Expect it in the `Authorization: Bearer <key>` header?
- (b) Have built-in middleware that reads `MCP_API_KEY` env var?
- (c) Require a separate auth proxy/sidecar?

**Your Answer**: The Neo4j MCP Server does not provide authentication and I do not want to use the mcp server per request authentication. Does Azure provide any built-in middleware for API key validation? Can you make some recommendations.

**Research Findings**: The Neo4j MCP server uses **HTTP Basic Authentication** (not API key), with these characteristics:
- Credentials can come from: (1) `Authorization: Basic base64(user:pass)` header, or (2) env var fallback
- Auth is **only required for `tools/call`** method (database operations)
- Auth is **not required for** `initialize` and `tools/list` (discovery)

**Azure Authentication Options for Container Apps:**

| Option | Complexity | Cost | Best For |
|--------|------------|------|----------|
| **A. Use Basic Auth directly** | Low | Free | Simple demo - Neo4j credentials authenticate requests |
| **B. Nginx sidecar** | Medium | Free | API key validation + proxy to MCP with Basic Auth |
| **C. Azure Easy Auth (Entra ID)** | Medium | Free | Enterprise SSO, Azure AD integration |
| **D. Azure API Management** | High | ~$50/mo | Rate limiting, subscriptions, analytics |

**Recommendation for Demo**:

**Option B - Nginx Sidecar** provides the API key interface you want:
1. Add an Nginx container as a sidecar in the Container App
2. Nginx validates `x-api-key` or `Authorization: Bearer <key>` header against `MCP_API_KEY`
3. If valid, Nginx proxies to the MCP server (localhost:8000) with Basic Auth credentials
4. This decouples authentication from the MCP server

**Alternative - Use Basic Auth directly** (simplest):
- Skip API key entirely and use HTTP Basic Auth with Neo4j credentials
- Clients send `Authorization: Basic base64(neo4j:password)`
- Downside: exposes database credentials to clients

See: [Host remote MCP servers in Azure Container Apps](https://techcommunity.microsoft.com/blog/appsonazureblog/host-remote-mcp-servers-in-azure-container-apps/4403550)

**Additional Answer**:  Option B - Nginx Sidecar
---

### Q4: Container Image Build Source

The deploy script needs to build the Docker image from the official Neo4j MCP repository.

**Question**: What is the correct Dockerfile path within the Neo4j MCP repository? Is it:
- (a) Root level `Dockerfile`?
- (b) Subdirectory like `docker/Dockerfile`?
- (c) A different location?

**Your Answer**: The .env has a NEO4J_MCP_REPO that is used to locate it. Review the Neo4j MCP server at /Users/ryanknight/projects/mcp to confirm the Dockerfile location.

**Research Findings**:
- **Location**: Root level `Dockerfile` at `${NEO4J_MCP_REPO}/Dockerfile`
- Multi-stage build using `golang:1.25-alpine` as builder
- Runtime uses minimal `scratch` image (non-root, UID 65532)
- Includes CA certificates for TLS connections to Neo4j Aura
- Entrypoint: `/app/neo4j-mcp`

**Additional Answer**: Use Research Findings: Location: Root level `Dockerfile` at `${NEO4J_MCP_REPO}/Dockerfile`
---

### Q5: Additional Environment Variables

Some MCP servers require additional configuration beyond database connection.

**Question**: Are there any additional environment variables needed for:
- Logging configuration?
- Feature flags?
- Connection pooling settings?
- Timeout configurations?

**Your Answer**: Review the Neo4j MCP server at /Users/ryanknight/projects/mcp to verify

**Research Findings - Complete Environment Variable List**:

| Variable | Default | Description |
|----------|---------|-------------|
| **Required (STDIO mode)** |||
| `NEO4J_URI` | - | Neo4j connection URI (e.g., `bolt://localhost:7687`) |
| `NEO4J_USERNAME` | - | Database username |
| `NEO4J_PASSWORD` | - | Database password |
| **Optional (Neo4j)** |||
| `NEO4J_DATABASE` | `neo4j` | Database name |
| `NEO4J_READ_ONLY` | `false` | Enable read-only mode |
| `NEO4J_TELEMETRY` | `true` | Enable telemetry |
| `NEO4J_LOG_LEVEL` | `info` | Log verbosity |
| `NEO4J_LOG_FORMAT` | `text` | Log format: `text` or `json` |
| `NEO4J_SCHEMA_SAMPLE_SIZE` | `100` | Nodes to sample for schema |
| **Transport & HTTP** |||
| `NEO4J_MCP_TRANSPORT` | `stdio` | Transport: `stdio` or `http` |
| `NEO4J_MCP_HTTP_HOST` | `127.0.0.1` | HTTP bind address |
| `NEO4J_MCP_HTTP_PORT` | `443`/`80` | HTTP port (443 with TLS) |
| `NEO4J_MCP_HTTP_ALLOWED_ORIGINS` | (empty) | CORS origins (comma-separated) |
| `NEO4J_MCP_HTTP_TLS_ENABLED` | `false` | Enable HTTPS |
| `NEO4J_MCP_HTTP_TLS_CERT_FILE` | - | TLS certificate path |
| `NEO4J_MCP_HTTP_TLS_KEY_FILE` | - | TLS private key path |

**HTTP Timeouts** (hardcoded in server):
- ReadTimeout: 15s
- WriteTimeout: 60s (for complex queries)
- IdleTimeout: 120s
- ReadHeaderTimeout: 5s (Slowloris protection)


**Additional Answer**: Keep it simple for demo and just use the required variables plus `NEO4J_DATABASE` `NEO4J_READ_ONLY` `NEO4J_SCHEMA_SAMPLE_SIZE` `NEO4J_LOG_LEVEL=info` for better logging.  Set NEO4J_MCP_TRANSPORT to http.


---

### Q6: Deployment Order for First-Time Setup

The current implementation has a chicken-and-egg situation: the Container App references an image that doesn't exist until it's built and pushed.

**Question**: Preferred approach for first deployment:
- (a) Deploy infrastructure first (will fail initially), then build/push image, then redeploy
- (b) Use a conditional deployment flag to skip Container App on first run
- (c) Build and push image before running any Bicep deployment

**Recommended**: Option (c) - Build and push first, then deploy all infrastructure

**Your Answer**: Option (c) - Build and push first, then deploy all infrastructure

**Implementation**: The deploy script will:
1. Deploy ACR first (minimal Bicep run)
2. Build and push image to ACR
3. Deploy full infrastructure including Container App

---

## References

- [Azure Container Apps Documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Container Apps Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.app/containerapps)
- [Azure Container Registry Documentation](https://learn.microsoft.com/en-us/azure/container-registry/)
- [Azure Key Vault Documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Managed Identities for Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [Key Vault Secrets in Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets)
- [Container Apps Ingress Configuration](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
- [Neo4j MCP Server Repository](https://github.com/neo4j/mcp)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
