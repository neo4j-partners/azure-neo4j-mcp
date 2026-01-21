# Azure Neo4j MCP Server

Deploy the Neo4j MCP (Model Context Protocol) server to Azure Container Apps. This project provides two deployment approaches to match different security requirements.

## Choose Your Implementation

| Implementation | Authentication | Best For |
|----------------|----------------|----------|
| [simple-mcp-server](./simple-mcp-server/) | Static API Key | Quick demos, development, scenarios without SSO |
| [bearer-mcp-server](./bearer-mcp-server/) | Bearer Token (SSO/OIDC) | Enterprise environments with identity providers |

### Simple MCP Server

Uses an Nginx authentication proxy with a static API key. Two-container architecture that is straightforward to deploy and understand.

**Choose this when:**
- You want to get started quickly
- You do not need SSO integration
- Static API key authentication is acceptable for your use case
- You are running demos or development workloads

**Quick Start:**
```bash
cd simple-mcp-server
cp .env.sample .env
# Edit .env with your Neo4j credentials
./scripts/deploy.sh
```

[Full documentation](./simple-mcp-server/README.md)

### Bearer Token MCP Server

Uses the Neo4j MCP server's native bearer token authentication. Single-container architecture that integrates with enterprise identity providers.

**Choose this when:**
- You need SSO integration (Microsoft Entra ID, Okta, etc.)
- Compliance requires user-level audit trails
- You want to leverage existing identity policies (MFA, conditional access)
- You prefer industry-standard OAuth 2.0/OIDC authentication

**Status:** Planned - see [BEARER_AUTH_V2.md](./BEARER_AUTH_V2.md) for implementation details.

[Placeholder documentation](./bearer-mcp-server/README.md)

## Project Structure

```
azure-neo4j-mcp/
├── simple-mcp-server/      # API key authentication (production ready)
│   ├── scripts/            # Deployment automation
│   ├── infra/              # Bicep infrastructure templates
│   ├── client/             # Test client
│   ├── samples/            # Agent samples and integrations
│   └── README.md           # Full documentation
│
├── bearer-mcp-server/      # Bearer token authentication (planned)
│   └── README.md           # Status and planned features
│
├── BEARER_AUTH_V2.md       # Implementation proposal and progress
└── README.md               # This file
```

## Prerequisites

Both implementations require:

- Azure subscription with permissions to create resources
- Azure CLI installed and authenticated
- Docker with buildx support
- A Neo4j database instance (Aura or self-hosted)
- The Neo4j MCP server source code

Additionally, bearer-mcp-server will require:
- Neo4j Enterprise Edition with OIDC configured, OR
- Neo4j Aura Enterprise with SSO enabled
- An OIDC-compliant identity provider

## Documentation

- [Simple MCP Server Documentation](./simple-mcp-server/README.md)
- [Architecture Overview](./simple-mcp-server/docs/ARCHITECTURE.md)
- [Bearer Token Proposal](./BEARER_AUTH_V2.md)

## Related Projects

- [Neo4j MCP Server](https://github.com/neo4j/mcp) - The upstream MCP server implementation
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
