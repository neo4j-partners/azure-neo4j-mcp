# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project deploys the Neo4j MCP (Model Context Protocol) server to Azure Container Apps. It provides two implementations:

- **simple-mcp-server**: API key authentication via Nginx proxy (two-container architecture)
- **bearer-mcp-server**: JWT bearer token authentication for SSO/OIDC (single-container, uses official `docker.io/mcp/neo4j` image from Docker Hub)

## Common Commands

### Simple MCP Server Deployment

```bash
cd simple-mcp-server

# Setup environment (prompts for Neo4j credentials)
./scripts/setup-env.sh

# Full deployment (infra + build + push + deploy)
./scripts/deploy.sh

# Rebuild and redeploy containers only
./scripts/deploy.sh redeploy

# Deploy infrastructure only
./scripts/deploy.sh infra

# Show deployment status
./scripts/deploy.sh status

# Test the deployment
./scripts/deploy.sh test

# View logs
./scripts/logs.sh 100

# Cleanup all resources
./scripts/cleanup.sh --force
```

### Bearer MCP Server Deployment

```bash
cd bearer-mcp-server

# Copy deployment config from azure-ee-template
cp /path/to/azure-ee-template/.deployments/standalone-v2025.json ./neo4j-deployment.json

# Setup environment
./scripts/setup-env.sh

# Deploy
./scripts/deploy.sh

# Test bearer token auth
./scripts/deploy.sh test
```

### Sample Agents

```bash
cd simple-mcp-server/samples

# Deploy Azure AI infrastructure
azd up

# Sync environment variables
uv run python setup_env.py

# LangGraph agent
cd langgraph-mcp-agent
uv sync
uv run python simple-agent.py

# MAF agent
cd sample-maf-agent
uv sync
uv run start-samples
```

## Architecture

### Two Container Implementations

| Implementation | Containers | Auth Method | Use Case |
|---------------|------------|-------------|----------|
| simple-mcp-server | Nginx proxy + MCP server | Static API key | Quick demos, development |
| bearer-mcp-server | MCP server only (Docker Hub) | JWT bearer tokens | Enterprise SSO with Neo4j OIDC |

### Infrastructure Stack (Bicep)

**simple-mcp-server** deploys: ACR, Key Vault, Log Analytics, Managed Identity, Container Apps Environment + Container App

**bearer-mcp-server** deploys: Key Vault, Log Analytics, Container Apps Environment + Container App (pulls official image directly from Docker Hub — no ACR or Managed Identity needed)

The `infra/` directory in each implementation contains:
- `main.bicep` - orchestrates all modules
- `main.bicepparam` - deployment parameters
- `modules/` - individual resource definitions

### Authentication Flows

**Simple MCP Server**: Client → Nginx (API key validation) → MCP Server → Neo4j (env var credentials)

**Bearer MCP Server**: Client → MCP Server (extracts JWT) → Neo4j (validates JWT against IdP JWKS)

## Key Files

- `MCP_ACCESS.json` - Generated after deployment, contains endpoint URL and API key
- `.env` / `.env.sample` - Environment configuration (never commit `.env`)
- `neo4j-deployment.json` - Bearer mode config from azure-ee-template

## MCP Tools Exposed

| Tool | Description |
|------|-------------|
| `get-schema` | Retrieve database schema |
| `read-cypher` | Execute read-only Cypher queries |
| `list-gds-procedures` | List Graph Data Science procedures |

## Development Notes

- **simple-mcp-server** requires the [neo4j-partners/mcp fork](https://github.com/neo4j-partners/mcp/tree/feat/http-env-credentials) with HTTP streaming environment variable support — clone it to `../mcp` relative to this project or set `NEO4J_MCP_REPO` in `.env`
- **bearer-mcp-server** uses the official `docker.io/mcp/neo4j:latest` image from Docker Hub — no local build or clone required
- Bicep templates use `bicepconfig.json` for Microsoft Graph extensions
- Sample agents use `uv` for Python package management
