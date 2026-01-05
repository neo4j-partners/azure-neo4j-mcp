# Neo4j MCP Server - Azure Container Apps Deployment Proposal v2

## Executive Summary

This proposal describes the deployment of the Neo4j MCP (Model Context Protocol) server to Azure Container Apps. The deployment enables AI agents such as Claude and GitHub Copilot to query Neo4j graph databases through the standardized Model Context Protocol.

The solution uses Azure-native infrastructure including Container Apps, Container Registry, Key Vault, and Log Analytics. A key architectural decision is the use of an Nginx reverse proxy sidecar to provide API key authentication, which keeps the authentication layer separate from the MCP server itself.

All implementation phases are complete. This document describes the architecture, implementation details, and deployment procedures.

---

## Problem Statement

Organizations using Azure as their primary cloud platform need a straightforward way to deploy MCP servers for AI agent integration. The current alternatives each have significant drawbacks:

Running the MCP server locally limits accessibility to the local machine and requires manual process management. Using non-Azure cloud providers introduces complexity when Azure is already the established platform. Building custom deployment solutions without a reference architecture leads to inconsistent implementations and potential security gaps.

This deployment provides a reusable pattern for Azure-based MCP server hosting with proper security, monitoring, and operational practices.

---

## Solution Overview

The Neo4j MCP server runs as a containerized application on Azure Container Apps. The deployment follows infrastructure-as-code principles using Bicep templates, ensuring repeatable and auditable deployments.

The core components are:

**Container Application**: The Neo4j MCP server runs in HTTP transport mode, listening on port 8000. It connects to a Neo4j Aura database using credentials stored securely in Azure Key Vault.

**Authentication Layer**: An Nginx reverse proxy runs as a sidecar container within the same Container App. This proxy validates API keys in incoming requests before forwarding them to the MCP server with the appropriate Basic Authentication credentials.

**Supporting Infrastructure**: Azure Container Registry stores the container images. Azure Key Vault manages all secrets. Log Analytics collects application logs and metrics. A user-assigned managed identity provides secure, credential-free access between Azure services.

---

## Architecture

### High-Level Component Diagram

The architecture consists of external clients communicating with an Azure Container App that hosts two containers working together. The first container is an Nginx reverse proxy that handles incoming requests and validates API keys. The second container is the Neo4j MCP server that processes MCP protocol requests and communicates with the Neo4j database.

External traffic enters through the Azure Container Apps ingress on HTTPS port 443. The ingress routes requests to the Nginx container listening on port 8080. Nginx validates the API key from the request header, and if valid, forwards the request to the MCP server on localhost port 8000 with Basic Authentication credentials injected. The MCP server then communicates with the Neo4j Aura database over an encrypted connection.

### Authentication Flow

The authentication flow works as follows:

First, an AI agent sends an MCP request to the Container App endpoint with an API key in the request header. The API key can be provided either as a Bearer token in the Authorization header or as an X-API-Key header value.

Second, the Nginx sidecar receives the request and extracts the API key. It compares this key against the configured MCP API key stored in the environment. If the keys do not match, Nginx returns a 401 Unauthorized response and the request stops here.

Third, if the API key is valid, Nginx constructs a new request to the MCP server. It removes the original Authorization header and replaces it with Basic Authentication credentials using the Neo4j username and password. This request goes to localhost port 8000.

Fourth, the MCP server receives the authenticated request and processes it. For tool calls that access the database, it uses the Basic Auth credentials to connect to Neo4j. For discovery requests like listing available tools, authentication is not required by the MCP server.

Fifth, the response flows back through the chain. The MCP server returns results to Nginx, which forwards them to the client.

This design means clients only need to know the API key. They never see or handle the Neo4j database credentials directly. The API key can be rotated independently of database credentials, and different API keys could potentially be issued to different clients in future enhancements.

### Container Communication

Both containers run within the same Container App pod, meaning they share a network namespace. The Nginx container can reach the MCP server using localhost, which provides fast, secure communication without any network traversal.

The Nginx container is the only one with an exposed port to the ingress. The MCP server listens only on localhost and cannot be reached directly from outside the pod. This provides defense in depth since even if someone bypassed the ingress, they could not directly access the MCP server without going through Nginx.

---

## Azure Resources

The deployment creates the following Azure resources:

### User-Assigned Managed Identity

A managed identity provides the Container App with secure access to other Azure services without storing credentials. This identity is granted two role assignments: AcrPull on the Container Registry to pull container images, and Key Vault Secrets User on the Key Vault to read secrets at runtime.

### Log Analytics Workspace

The workspace collects container logs and metrics from the Container Apps Environment. It provides query capabilities for troubleshooting and monitoring. Log retention is set to 30 days to minimize costs for this demo deployment.

### Azure Container Registry

The registry stores two container images: the Neo4j MCP server image built from the official repository, and a custom Nginx image configured for API key validation. The registry uses the Basic SKU which provides sufficient storage and throughput for demo purposes. Admin authentication is disabled in favor of managed identity access.

### Azure Key Vault

The Key Vault stores five secrets: the Neo4j connection URI, username, password, and database name, plus the MCP API key used for client authentication. RBAC authorization is enabled rather than access policies, following current Azure best practices. Soft delete is enabled with a 7-day retention period, but purge protection is disabled to allow complete cleanup during development.

### Container Apps Environment

The environment provides the networking and compute infrastructure for the Container App. It uses the Consumption workload profile, which provides serverless scaling and pay-per-use pricing. Zone redundancy is disabled for this demo to reduce costs.

### Container App

The Container App runs two containers: the Nginx sidecar and the Neo4j MCP server. It is configured with exactly one replica, providing consistent performance without cold start delays during demonstrations. The app uses the managed identity to pull images from the Container Registry and read secrets from Key Vault.

---

## Environment Configuration

### Required Configuration Variables

The deployment requires the following configuration, typically stored in a local environment file:

**Azure Settings**: The Azure subscription ID, resource group name, and deployment region must be specified. The resource group will be created if it does not exist.

**Neo4j Connection**: The Neo4j URI specifies the database connection string, typically in the format neo4j+s://xxx.databases.neo4j.io for Aura databases. The username, password, and database name complete the connection configuration.

**MCP Authentication**: The MCP API key is a secret string that clients must provide to access the server. This should be a randomly generated string of at least 32 characters.

**Build Configuration**: The path to the local Neo4j MCP repository is needed for building the container image.

### Runtime Environment Variables

The MCP server container receives these environment variables at runtime:

The Neo4j connection variables (URI, username, password, database) are injected from Key Vault secrets. The transport is set to HTTP mode with the host binding to all interfaces on port 8000. Logging is configured for JSON format at the info level to support structured log analysis in Log Analytics.

The Nginx container receives the MCP API key and Neo4j credentials to perform its authentication and proxy functions.

---

## Implementation Status

All phases are complete. The deployment is ready for use.

### Completed Work

**Phase One - Foundation Infrastructure**: All foundational resources are deployed and validated. The managed identity is created with proper role assignments. The Log Analytics workspace is configured with 30-day retention. The Container Registry is provisioned with managed identity authentication.

**Phase Two - Secrets Management**: The Key Vault module is complete with RBAC authorization enabled. All five secrets are created during deployment. The managed identity has the Key Vault Secrets User role.

**Phase Three - Container Environment**: The Container Apps Environment is deployed and linked to Log Analytics. The Consumption workload profile is configured for cost-effective scaling.

**Phase Four - Container App with Nginx Sidecar**: The Container App module includes both the Neo4j MCP server and the Nginx auth proxy sidecar. The Nginx container validates API keys using Lua scripts and proxies authenticated requests to the MCP server with Basic Auth credentials. The ingress routes external traffic through Nginx on port 8080, which forwards to the MCP server on localhost port 8000. Health probes are configured for both containers.

**Phase Five - Deployment Script**: The deployment script (scripts/deploy.sh) orchestrates the complete deployment workflow. It supports commands for building images, pushing to ACR, deploying infrastructure, checking status, running tests, and cleanup. The script handles the phased deployment required for first-time setup and generates an MCP_ACCESS.json file with connection information.

**Phase Six - Test Client**: The test client (client/test_client.py) validates the deployment end-to-end. It tests authentication rejection (no key and invalid key), MCP protocol connectivity via tools/list, schema retrieval via get-schema, and query execution via read-cypher.

---

## Implementation Details

### Nginx Sidecar Configuration

The Nginx sidecar uses OpenResty with Lua scripting for API key validation. The configuration is located at `scripts/nginx/nginx.conf`.

**Authentication Logic**: The Nginx configuration extracts the API key from either the Authorization Bearer header or the X-API-Key header. It compares the key against the MCP_API_KEY environment variable using Lua. Invalid or missing keys receive a 401 Unauthorized response with a JSON error message.

**Proxy Configuration**: For authenticated requests, Nginx constructs Basic Auth credentials from the NEO4J_USERNAME and NEO4J_PASSWORD environment variables. It forwards requests to the MCP server at `http://127.0.0.1:8000` with these credentials in the Authorization header.

**Health Endpoints**: The Nginx configuration provides `/health` and `/ready` endpoints that return 200 OK for container health probes.

**Container Image**: The Nginx image is built from `openresty/openresty:1.25.3.2-alpine` with the custom configuration. The Dockerfile is at `scripts/nginx/Dockerfile`.

### Deployment Script

The deployment script at `scripts/deploy.sh` provides a complete deployment workflow.

**Available Commands**:
- `./scripts/deploy.sh` - Full deployment (build, push, infrastructure, status)
- `./scripts/deploy.sh build` - Build container images locally
- `./scripts/deploy.sh push` - Push images to Azure Container Registry
- `./scripts/deploy.sh infra` - Deploy Bicep infrastructure templates
- `./scripts/deploy.sh status` - Show deployment status and outputs
- `./scripts/deploy.sh test` - Run the test client
- `./scripts/deploy.sh cleanup` - Delete all Azure resources
- `./scripts/deploy.sh help` - Display usage information

**Phased Deployment**: For first-time deployments, the script deploys foundation resources (managed identity, Log Analytics, ACR, Key Vault, Container Environment) first, then builds and pushes images, then deploys the Container App.

**Output Generation**: After successful deployment, the script generates `MCP_ACCESS.json` with the endpoint URL, MCP path, and API key placeholder.

### Test Client

The test client at `client/test_client.py` validates the deployment with these tests:

1. **Authentication Rejection (No Key)**: Verifies requests without API key receive 401
2. **Authentication Rejection (Invalid Key)**: Verifies requests with wrong API key receive 401
3. **Tools List**: Calls tools/list to verify MCP protocol connectivity
4. **Get Schema**: Calls get-schema to verify Neo4j database connectivity
5. **Read Cypher**: Executes `RETURN 1 as value` to verify query execution

The client reads configuration from `MCP_ACCESS.json` and the `.env` file for the API key.

---

## Deployment Workflow

### First-Time Deployment

The first-time deployment follows this sequence:

1. Verify prerequisites are met: Azure CLI is installed and authenticated, Docker is available with buildx support, the Neo4j MCP repository is cloned locally, and the environment file is configured.

2. Run the deployment script with no arguments. The script will detect this is a first-time deployment and execute the phased approach.

3. The script deploys the managed identity, Log Analytics, Key Vault, and Container Registry. These resources do not depend on the container images.

4. The script builds the Neo4j MCP server image from the local repository using the provided Dockerfile.

5. The script builds the Nginx sidecar image with the authentication configuration.

6. The script authenticates to ACR and pushes both images.

7. The script deploys the Container Apps Environment and Container App, referencing the newly pushed images.

8. The script generates the MCP access file with connection information.

9. The script runs the test client to verify the deployment.

### Subsequent Deployments

After the initial deployment, updates follow a simpler process:

1. If infrastructure changes are needed, run the script with the infra command to update the Bicep deployment.

2. If image changes are needed, run build and push commands, then restart the Container App to pick up the new images.

3. The full deployment command will detect existing resources and perform incremental updates rather than creating everything from scratch.

### Cleanup

To remove the deployment, run the script with the cleanup command. This will delete the entire resource group, removing all Azure resources. Note that Key Vault will enter soft-deleted state and can be recovered for 7 days if needed.

---

## Testing Strategy

### Automated Validation

The test client performs automated validation of the deployment:

**Connectivity Test**: Verifies the endpoint is reachable and responds to requests.

**Authentication Test**: Verifies that requests without an API key are rejected with 401 status, and requests with the correct API key are accepted.

**Discovery Test**: Calls the tools/list endpoint to verify the MCP protocol is working and returns the expected tools.

**Schema Test**: Calls get-schema to verify the server can connect to Neo4j and retrieve database schema information.

**Query Test**: Executes a simple read-only Cypher query to verify end-to-end data flow.

### Manual Validation

Additional manual validation should be performed:

**Log Verification**: Check Log Analytics to verify logs are being collected from both containers.

**Error Handling**: Test with invalid API keys, malformed requests, and network interruptions to verify appropriate error responses.

**Performance Check**: Execute several requests in sequence to verify consistent response times.

---

## Cost Estimate

The monthly cost for this demo deployment is estimated as follows:

**Container Apps**: With one always-running instance using 0.5 vCPU and 1 GB memory, the cost is approximately 15 to 30 dollars depending on actual CPU utilization.

**Container Registry**: The Basic SKU costs 5 dollars per month with 10 GB of storage included.

**Key Vault**: With minimal operations for this demo, the cost is approximately 50 cents per month.

**Log Analytics**: With low log volume from a single instance, the cost is approximately 2 to 5 dollars per month.

**Total**: The estimated monthly cost is 25 to 40 dollars for demo usage.

Production deployments with multiple instances, higher traffic, or additional features would have proportionally higher costs.

---

## Security Considerations

### Defense in Depth

The deployment implements multiple layers of security:

**Network Security**: All external traffic uses HTTPS with TLS certificates managed by Azure. The MCP server is not directly exposed; all requests must go through the Nginx proxy.

**Authentication**: API key validation prevents unauthorized access. Basic Auth credentials are injected by the proxy, never exposed to clients.

**Secrets Management**: All sensitive values are stored in Key Vault, never in code or configuration files. Secrets are retrieved at runtime using managed identity.

**Identity and Access**: The managed identity follows least-privilege principles, having only the specific permissions needed for its functions.

### Security Recommendations

For production deployments, consider these additional measures:

**API Key Rotation**: Implement a process for regular API key rotation without service interruption.

**Network Isolation**: Consider adding Virtual Network integration to restrict database connectivity to private endpoints.

**Monitoring and Alerting**: Set up alerts for authentication failures, unusual traffic patterns, or error rate increases.

**Audit Logging**: Enable diagnostic settings to capture detailed audit logs for compliance requirements.

---

## Risks and Mitigations

### Technical Risks

**Container Image Build Failures**: The Neo4j MCP server Dockerfile may have dependencies that fail to resolve. Mitigation: Test the build locally before automating, and pin specific versions where possible.

**Key Vault Access Timing**: The managed identity role assignment may not propagate immediately, causing initial secret retrieval failures. Mitigation: Include retry logic in the container startup.

**Nginx Configuration Errors**: Misconfigured proxy settings could block all traffic or bypass authentication. Mitigation: Test the configuration thoroughly in isolation before deployment.

### Operational Risks

**Secret Exposure**: Secrets could be exposed through logs, error messages, or debugging output. Mitigation: Configure logging to redact sensitive values, and review all output paths.

**Resource Cleanup**: Soft-deleted Key Vault could prevent redeployment with the same name. Mitigation: Use unique names or purge soft-deleted vaults before redeployment.

**Cost Overruns**: Unexpected usage patterns could increase costs. Mitigation: Set up budget alerts and review usage regularly.

---

## Next Steps

The implementation is complete. To deploy the Neo4j MCP Server to Azure:

1. **Configure Environment**: Copy `.env.example` to `.env` and fill in your Neo4j Aura credentials, Azure subscription details, and generate an MCP API key.

2. **Clone Neo4j MCP Repository**: Clone the official Neo4j MCP server repository to the path specified in `NEO4J_MCP_PATH` in your `.env` file.

3. **Run Deployment**: Execute `./scripts/deploy.sh` to perform the full deployment. The script will build images, deploy infrastructure, and generate the access configuration.

4. **Validate Deployment**: Run `./scripts/deploy.sh test` to verify the deployment is working correctly.

5. **Configure AI Agents**: Use the generated `MCP_ACCESS.json` file to configure Claude, GitHub Copilot, or other MCP-compatible AI agents to connect to your deployed server.

For subsequent updates, use the individual script commands (build, push, infra) as needed.

---

## References

Azure Container Apps Documentation: https://learn.microsoft.com/en-us/azure/container-apps/

Azure Container Apps Bicep Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.app/containerapps

Azure Container Registry Documentation: https://learn.microsoft.com/en-us/azure/container-registry/

Azure Key Vault Documentation: https://learn.microsoft.com/en-us/azure/key-vault/

Managed Identities for Azure Container Apps: https://learn.microsoft.com/en-us/azure/container-apps/managed-identity

Key Vault Secrets in Container Apps: https://learn.microsoft.com/en-us/azure/container-apps/manage-secrets

Container Apps Ingress Configuration: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview

Host Remote MCP Servers in Azure Container Apps: https://techcommunity.microsoft.com/blog/appsonazureblog/host-remote-mcp-servers-in-azure-container-apps/4403550

Neo4j MCP Server Repository: https://github.com/neo4j/mcp

Model Context Protocol Specification: https://modelcontextprotocol.io/
