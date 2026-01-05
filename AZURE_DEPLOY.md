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

### Phase 2: Secrets and Security

1. Create Bicep module for Azure Key Vault with RBAC authorization enabled
2. Configure RBAC role assignment granting managed identity Key Vault Secrets User permission
3. Create secrets for Neo4j connection parameters and MCP API key
4. Validate managed identity can retrieve secrets

### Phase 3: Container Environment

1. Create Bicep module for Container Apps Environment linked to Log Analytics
2. Configure environment for consumption-based workload profile
3. Validate environment creation and logging integration

### Phase 4: Container App

1. Create Bicep module for Container App with fixed 1 replica
2. Configure managed identity for image pull authentication
3. Configure Key Vault references for all environment variables including MCP_API_KEY
4. Set container resource limits (CPU: 0.5, Memory: 1Gi)
5. Configure HTTP ingress on port 8000 with external access
6. Configure API key validation using the MCP_API_KEY from Key Vault
7. Validate container starts and responds to authenticated requests

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
