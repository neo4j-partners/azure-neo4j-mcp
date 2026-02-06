# Azure Neo4j MCP Server

Deploy the Neo4j MCP (Model Context Protocol) server to Azure Container Apps.

> **Disclaimer:** This is a **sample template** provided as-is for demonstration and learning purposes. It is **not officially supported** and requires full security hardening and review before any production use.

## Recommended: Bearer Token MCP Server

The [bearer-mcp-server](./bearer-mcp-server/) is the recommended deployment. It uses the **official `mcp/neo4j` Docker image** from Docker Hub with native bearer token authentication for SSO/OIDC integration.

**Features:**
- Official Docker image — no custom builds required
- Single-container architecture
- JWT bearer token authentication via Microsoft Entra ID, Okta, or any OIDC provider
- Per-user identity and audit trails
- Integrates with [azure-ee-template](https://github.com/neo4j-partners/azure-ee-template) M2M authentication

**Quick Start:**
```bash
cd bearer-mcp-server

# Copy deployment config from azure-ee-template
cp /path/to/azure-ee-template/.deployments/standalone-v2025.json ./neo4j-deployment.json

# Setup and deploy
./scripts/setup-env.sh
./scripts/deploy.sh
```

[Full documentation](./bearer-mcp-server/README.md)

---

## Alternative: Simple MCP Server (Demo Only)

The [simple-mcp-server](./simple-mcp-server/) is a basic demo deployment using static API key authentication via an Nginx proxy.

**Limitations:**
- Requires a [modified fork](https://github.com/neo4j-partners/mcp/tree/feat/http-env-credentials) of the MCP server (not the official image)
- Two-container architecture (Nginx + MCP server)
- Static API key shared across all callers
- No per-user identity or audit trails

**Use this only for:**
- Quick demos without SSO requirements
- Development and testing

[Documentation](./simple-mcp-server/README.md)

## Project Structure

```
azure-neo4j-mcp/
├── bearer-mcp-server/      # Recommended: Bearer token auth (official image)
│   ├── scripts/            # Deployment automation
│   ├── infra/              # Bicep infrastructure templates
│   ├── client/             # Test client
│   └── README.md           # Full documentation
│
├── simple-mcp-server/      # Demo only: API key auth (requires fork)
│   ├── scripts/            # Deployment automation
│   ├── infra/              # Bicep infrastructure templates
│   ├── client/             # Test client
│   ├── samples/            # Agent samples and integrations
│   └── README.md           # Full documentation
│
├── local_http_validation/  # Local testing for HTTP mode
└── README.md               # This file
```

## Prerequisites

### Bearer MCP Server (Recommended)

- Azure subscription with permissions to create resources
- Azure CLI installed and authenticated
- Neo4j Enterprise Edition with OIDC configured (via [azure-ee-template](https://github.com/neo4j-partners/azure-ee-template))
- An OIDC-compliant identity provider (Microsoft Entra ID, Okta, etc.)

### Simple MCP Server (Demo)

- Azure subscription with permissions to create resources
- Azure CLI installed and authenticated
- Docker with buildx support
- The [neo4j-partners/mcp fork](https://github.com/neo4j-partners/mcp/tree/feat/http-env-credentials) cloned locally
- A Neo4j database instance (Aura or self-hosted)

## Related Projects

- [Neo4j MCP Server](https://github.com/neo4j/mcp) - The official MCP server implementation
- [azure-ee-template](https://github.com/neo4j-partners/azure-ee-template) - Neo4j Enterprise Azure deployment with M2M auth
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
