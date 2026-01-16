# Sample Agents

This directory contains sample agent implementations that demonstrate how to connect to and use the Neo4j MCP server with Azure AI.

## Architecture

The samples have their **own separate Azure infrastructure** for AI models:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Project Root (/)                    │  Samples (/samples)              │
├─────────────────────────────────────────────────────────────────────────┤
│  Neo4j MCP Server Infrastructure     │  Azure AI Infrastructure         │
│  ├── Container Apps                  │  ├── Azure AI Services           │
│  ├── Container Registry              │  ├── Azure AI Project            │
│  ├── Key Vault                       │  ├── GPT-4o Deployment           │
│  └── Log Analytics                   │  └── Embedding Deployment        │
│                                      │                                  │
│  Deploy: ./scripts/deploy.sh         │  Deploy: azd up (from samples/)  │
│  Cleanup: ./scripts/cleanup.sh       │  Cleanup: azd down               │
└─────────────────────────────────────────────────────────────────────────┘
```

**Why separate?** The MCP server is a standalone service that can be used by any AI client. The samples deploy their own Azure AI Foundry models to demonstrate usage, but you could use any LLM provider (OpenAI, Anthropic, local models, etc.) with the MCP server.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) installed
- [uv](https://docs.astral.sh/uv/) (Python package manager)
- Python 3.10+
- Neo4j database (e.g., [Neo4j Aura](https://neo4j.com/cloud/aura/))

## Quick Start

**Note:** This assumes you have already deployed the Neo4j MCP server from the project root using `./scripts/deploy.sh`.

### 1. Deploy Azure AI Infrastructure

From the `samples/` directory:

```bash
# Configure Azure region and initialize azd environment
./scripts/setup_azure.sh

# Login to Azure
az login
azd auth login

# Deploy AI Services (gpt-4o + text-embedding-ada-002)
azd up

# Sync environment variables (Azure AI + MCP from MCP_ACCESS.json)
uv run python setup_env.py
```

**Authentication:** The samples use `AzureCliCredential` which authenticates using your `az login` identity. The Bicep deployment assigns the necessary RBAC roles (Cognitive Services User, Azure AI Developer) to your Azure account.

### 2. Run a Sample

```bash
cd langgraph-mcp-agent
uv sync
uv run python simple-agent.py

# Or ask a specific question
uv run python simple-agent.py "How many nodes are in the database?"
```

## Samples

### langgraph-mcp-agent

A LangGraph-based ReAct agent that connects to the Neo4j MCP server using Azure OpenAI.

**Features:**
- Uses `langchain-mcp-adapters` for MCP tool integration
- Azure OpenAI (GPT-4o) for LLM inference with Azure CLI authentication
- Simple CLI interface with demo queries

**Files:**
- `simple-agent.py` - Main agent implementation
- `LANGGRAPH_BEST_PRACTICES.md` - Guide for LangGraph v1 API usage
- `pyproject.toml` - Python dependencies

---

### sample-maf-agent

Sample applications using the Microsoft Agent Framework (MAF) with the [`agent-framework-neo4j`](https://github.com/neo4j-partners/neo4j-maf-provider) provider and [Neo4j context provider](https://github.com/neo4j-partners/neo4j-maf-provider). This sample creates the `api-arches-agent` in Azure AI Foundry.

**How it works:**
- Uses the `agent-framework-neo4j` provider package which extends MAF with Neo4j-powered knowledge retrieval
- Leverages the Neo4j context provider to inject graph context into agent conversations
- The provider implements custom `KnowledgeAgent` and `KnowledgeAgentOutput` classes that wrap Neo4j search capabilities
- Supports multiple retrieval strategies: fulltext search, vector/semantic search, and graph-enriched search
- The agent is registered in Azure AI Foundry as `api-arches-agent` (configurable via `AZURE_AI_AGENT_NAME` env var)

**Features:**
- Multiple search strategies (fulltext, vector, graph-enriched)
- Azure AI Foundry integration with persistent agent registration
- Financial document analysis use case

**Run:**

```bash
cd sample-maf-agent
uv sync

# Run samples using the CLI
uv run start-samples
```

**Files:**
- `src/samples/basic_fulltext/` - Basic fulltext search sample (not working)
- `src/samples/vector_search/` - Vector/semantic search sample
- `src/samples/graph_enriched/` - Graph-enriched search sample
- `src/samples/shared/` - Shared utilities and agent configuration

## Configuration

All samples share a common `.env` file in the `samples/` directory:

| Variable | Description | Source |
|----------|-------------|--------|
| `AZURE_AI_SERVICES_ENDPOINT` | Azure AI Services endpoint | `azd up` + `setup_env.py` |
| `AZURE_AI_MODEL_NAME` | Chat model deployment name | `azd up` + `setup_env.py` |
| `AZURE_AI_EMBEDDING_NAME` | Embedding model deployment | `azd up` + `setup_env.py` |
| `MCP_ENDPOINT` | Neo4j MCP server URL | `MCP_ACCESS.json` |
| `MCP_API_KEY` | MCP server API key | `MCP_ACCESS.json` |
| `NEO4J_URI` | Neo4j database URI | Manual configuration |
| `NEO4J_USERNAME` | Neo4j username | Manual configuration |
| `NEO4J_PASSWORD` | Neo4j password | Manual configuration |

## Infrastructure

The `infra/` directory contains Bicep templates for deploying Azure AI infrastructure:

```
samples/
├── infra/
│   ├── main.bicep              # AI Services + Project + Model deployments
│   └── main.parameters.json    # Deployment parameters
├── scripts/
│   └── setup_azure.sh          # Azure region configuration
├── setup_env.py                # Sync azd outputs to .env
└── azure.yaml                  # Azure Developer CLI configuration
```

### Deployed Resources

| Resource | Purpose |
|----------|---------|
| Azure AI Services | Hosts model deployments |
| Azure AI Project | Manages serverless endpoints |
| GPT-4o Deployment | Chat completion model |
| text-embedding-ada-002 | Embedding model |
| Storage Account | Required by AI Services |

### Supported Regions

Azure AI Foundry serverless models require one of these regions:
- `eastus2` (East US 2) - Recommended
- `swedencentral` (Sweden Central)
- `westus2` (West US 2)
- `westus3` (West US 3)

## Cleanup

To remove the Azure AI infrastructure:

```bash
cd samples
azd down
```

To remove the MCP server (from project root):

```bash
cd ..
./scripts/cleanup.sh
```
