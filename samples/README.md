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
- Neo4j database (e.g., [Neo4j Aura](https://neo4j.com/cloud/aura/)) - see [SETUP.md](SETUP.md) for database setup instructions

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

#### LangGraph MCP Agent

```bash
cd langgraph-mcp-agent
uv sync
uv run python simple-agent.py

# Or ask a specific question
uv run python simple-agent.py "How many nodes are in the database?"
```

#### Microsoft Agent Framework (MAF) Sample

```bash
cd sample-maf-agent
uv sync

# Run samples using the CLI
uv run start-samples
```

## Overview of Samples

### langgraph-mcp-agent

This sample demonstrates how to build a conversational AI agent using LangGraph that can query and explore a Neo4j graph database through the MCP server.

The agent uses a ReAct (Reasoning and Acting) pattern, which means it can reason about what tools to use, execute them, observe the results, and continue reasoning until it has enough information to answer your question. When you ask the agent a question about your graph data, it automatically discovers available MCP tools, selects the appropriate ones, and executes Cypher queries against your Neo4j database.

The sample uses Azure OpenAI's GPT-4o model for the language model and connects to the MCP server using LangChain's MCP adapter library. Authentication is handled through the Azure CLI, so you don't need to manage API keys separately.

This is a good starting point if you want to understand the basics of connecting an LLM to the Neo4j MCP server, or if you prefer using the LangChain/LangGraph ecosystem.

---

### sample-maf-agent

This sample showcases the Microsoft Agent Framework (MAF) integration with Neo4j, demonstrating enterprise-grade agent development within the Azure AI Foundry ecosystem.

The sample uses a specialized Neo4j provider package that extends MAF with graph-powered knowledge retrieval capabilities. When deployed, it registers a persistent agent in Azure AI Foundry that can be accessed through the Azure AI platform. This makes it suitable for production scenarios where you need centralized agent management and monitoring.

The sample includes three different retrieval strategies to demonstrate various ways of searching graph data:

- **Fulltext search** finds documents by matching keywords and phrases against indexed text content in your graph nodes.

- **Vector search** uses semantic embeddings to find conceptually similar content, even when the exact words don't match. This is useful for natural language queries where meaning matters more than exact terminology.

- **Graph-enriched search** combines vector similarity with graph traversal to not only find relevant nodes but also explore their relationships and connected context. This provides richer answers by leveraging the graph structure.

The sample is designed around a financial document analysis use case, making it a good reference for building knowledge assistants that need to reason over interconnected business documents.

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

## Future Improvements

The following improvements are planned to enhance the sample agents. See `sample-maf-agent/IMPROVE.md` for implementation details.

### OpenTelemetry Observability Support

Add distributed tracing using OpenTelemetry to provide visibility into agent execution:
- Optional `--trace` flag to enable tracing
- OTLP exporter for trace collection
- Trace ID printing for debugging
- Integration with Azure Monitor / Aspire Dashboard

### DevUI Support for Interactive Debugging

Add the MAF DevUI for visual agent debugging:
- `uv run start-samples devui` command
- Visual conversation history
- Interactive testing interface
- Real-time agent state inspection

### Streaming Response Support

Add streaming responses for better user experience:
- Optional `--stream` flag to enable streaming
- Use `agent.run_stream()` instead of `agent.run()`
- Real-time token output as responses generate

### Enhanced Error Handling with Graceful Degradation

Improve error handling to allow agents to continue on partial failures:
- Return error info instead of raising exceptions
- Truncate long error messages for readability
- Allow demos to continue with partial results

### Custom Tools with @ai_function Decorator

When adding custom tools to agents, use the `@ai_function` decorator pattern:

```python
from agent_framework import ai_function
from typing import Annotated

@ai_function(description="Search the Neo4j knowledge graph")
def search_knowledge_graph(
    query: Annotated[str, "The search query"],
    top_k: Annotated[int, "Maximum results"] = 5,
) -> dict[str, Any]:
    """Search the knowledge graph and return results."""
    return {"query": query, "results": [...]}
```
