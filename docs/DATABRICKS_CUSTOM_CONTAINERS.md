# Proposal: Hosting MCP Server Directly in Databricks Using Custom Containers

## Executive Summary

**Short Answer: No, Databricks custom containers are not designed for hosting MCP servers and will not work for this purpose.**

Databricks custom containers are built for running Spark compute workloads (data processing, ML training), not for hosting persistent HTTP services. The current architecture in `simple-mcp-server/` — running the MCP server externally in Azure Container Apps and connecting via Unity Catalog HTTP proxy — is the correct and intended approach.

---

## What the Current Architecture Does

The `simple-mcp-server/` project deploys a Neo4j MCP server to Azure with this setup:

```
Databricks Workspace
       |
       v
Unity Catalog HTTP Connection (acts as proxy)
       |
       v
Azure Container Apps
├── Nginx Auth Proxy (port 8080)
│   - API key validation
│   - Rate limiting (10 req/sec)
│   - Security headers
│   |
│   v (localhost:8000)
└── Neo4j MCP Server (Go binary)
       |
       v
Neo4j Database (Aura or self-hosted)
```

**Why this design exists:**
- Databricks notebooks and agents call the MCP server through Unity Catalog's HTTP Connection feature
- Unity Catalog handles credential injection (Bearer token from secrets)
- The MCP server runs externally because Databricks cannot host it internally

---

## Why Databricks Custom Containers Will Not Work

### What Custom Containers Actually Are

Databricks custom containers are **compute environment customizations for Spark clusters**, not a general-purpose container hosting platform. Their purpose is to:

- Install custom system libraries for data processing
- Create "golden" locked-down environments for compliance
- Support custom GPU/ML frameworks for training jobs

### Critical Limitations

| Requirement | MCP Server Needs | Databricks Custom Containers |
|-------------|------------------|------------------------------|
| Listen on ports | Yes (HTTP on port 8000) | Not supported |
| Accept incoming connections | Yes (clients call the server) | Not supported |
| Run as a persistent service | Yes (always-on HTTP server) | Not supported |
| Use Docker CMD/ENTRYPOINT | Yes (starts the Go binary) | Explicitly ignored by Databricks |
| Keep running between requests | Yes (maintains Neo4j connection) | Containers exist only during job execution |

### What Databricks Does With Custom Containers

From the documentation:
1. VM acquired from cloud provider
2. Custom Docker image downloaded
3. Container created from image
4. **Databricks Runtime code copied INTO container**
5. Init scripts run
6. Spark executor starts

> "Databricks ignores the Docker CMD and ENTRYPOINT primitives"

This means Databricks takes over your container to run Spark workloads. You cannot run your own service.

### No Networking For Services

The documentation contains **zero mention** of:
- Exposing ports
- Accepting incoming HTTP requests
- Running background services
- Long-running daemons

This is because custom containers are not designed for these use cases.

---

## Why Databricks Apps Also Won't Work

Databricks Apps is their serverless application hosting, but it only supports:
- Python (Streamlit, Dash, Gradio)
- Node.js (React, Angular, Express)

The Neo4j MCP server is a **Go binary**. You cannot run Go code in Databricks Apps.

---

## Why Model Serving Won't Work

Databricks Model Serving is designed for:
- MLflow-packaged Python models
- Foundation model endpoints

It cannot run arbitrary Go services.

---

## The Current Design is Correct

The `simple-mcp-server/` architecture represents the **intended and correct approach** for using MCP servers with Databricks:

1. **MCP servers run externally** — in Azure Container Apps, AWS ECS, Google Cloud Run, or any container platform that can host HTTP services

2. **Databricks connects via Unity Catalog HTTP Connection** — this is the official integration point for external HTTP APIs

3. **Security handled at both ends**:
   - Azure: API key validation, rate limiting, TLS
   - Databricks: Secrets stored in secret scope, injected by Unity Catalog

---

## Alternative Approaches (If You Must Run Inside Databricks)

### Option 1: Python MCP Server (Hypothetical)

If Neo4j had a Python MCP server, you could potentially:
- Package it as a Databricks App (Streamlit/Dash wrapper)
- Deploy to Model Serving (if MLflow-compatible)

**Reality:** Neo4j's official MCP server is Go only. There is no Python implementation.

### Option 2: MCP Client Inside Databricks (Current Approach)

Instead of hosting the server in Databricks, host the **client** there:
- Use `langchain-mcp-adapters` in Python notebooks
- Agent runs in Databricks, calls external MCP server
- This is exactly what `databrick_samples/neo4j_mcp_agent.py` does

### Option 3: Direct Neo4j Access (Skip MCP)

If MCP is not required:
- Use `neo4j` Python driver directly in notebooks
- Build custom tools in LangChain/LangGraph
- Loses MCP protocol benefits but simpler architecture

---

## Conclusion

**Databricks custom containers are fundamentally incompatible with hosting MCP servers.** They are compute environments for Spark workloads, not container hosting platforms.

The `simple-mcp-server/` architecture is not a workaround — it is the correct design:

| Component | Where It Runs | Why |
|-----------|---------------|-----|
| Neo4j MCP Server | Azure Container Apps | Needs to accept HTTP connections, run persistently |
| Unity Catalog HTTP Connection | Databricks | Official proxy for external HTTP APIs |
| AI Agent (LangGraph) | Databricks notebooks/jobs | Calls MCP server through HTTP Connection |
| Neo4j Database | Neo4j Aura | Managed graph database |

**Recommendation:** Continue using the external hosting approach. It is secure, scalable, and follows Databricks' intended integration patterns.

---

## Summary Table

| Hosting Option | Can Run MCP Server? | Why/Why Not |
|----------------|---------------------|-------------|
| Databricks Custom Containers | No | Designed for Spark compute, ignores Docker CMD/ENTRYPOINT, no port exposure |
| Databricks Apps | No | Python/Node.js only, no Go support |
| Databricks Model Serving | No | MLflow models only, not arbitrary services |
| Azure Container Apps | Yes | Full container hosting, HTTP ingress, persistent services |
| AWS ECS/Fargate | Yes | Same capabilities as Azure |
| Google Cloud Run | Yes | Same capabilities as Azure |
| Self-hosted Kubernetes | Yes | Full control over container orchestration |

---

## References

- Databricks Custom Containers: https://docs.databricks.com/aws/en/compute/custom-containers
- Databricks Apps: https://docs.databricks.com/en/dev-tools/databricks-apps/
- Neo4j MCP Server: /Users/ryanknight/projects/mcp (Go binary, HTTP/STDIO transport)
- Current Architecture: /Users/ryanknight/projects/azure/azure-neo4j-mcp/simple-mcp-server/
