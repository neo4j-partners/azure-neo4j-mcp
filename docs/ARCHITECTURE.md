# Architecture Documentation

This document provides a detailed architectural overview of deploying the official Neo4j MCP (Model Context Protocol) server to Azure and extending it for Databricks integration.

## Table of Contents

- [Overview](#overview)
- [Neo4j MCP Server](#neo4j-mcp-server)
  - [Core Architecture](#core-architecture)
  - [Available Tools](#available-tools)
  - [Transport Modes](#transport-modes)
  - [Authentication](#authentication)
- [Azure Deployment](#azure-deployment)
  - [Resource Architecture](#resource-architecture)
  - [Container Architecture](#container-architecture)
  - [Security Model](#security-model)
  - [Deployment Flow](#deployment-flow)
- [Databricks Extension](#databricks-extension)
  - [Unity Catalog Integration](#unity-catalog-integration)
  - [Agent Deployment](#agent-deployment)
- [Request Flows](#request-flows)

---

## Overview

This project deploys the official Neo4j MCP server to Azure Container Apps, enabling AI agents to securely query Neo4j graph databases through the standardized Model Context Protocol. The architecture supports multiple client types including Claude Desktop, custom LangGraph agents, and Databricks notebooks.

```mermaid
graph TB
    subgraph Clients["AI Clients"]
        CD["Claude Desktop<br/>(STDIO)"]
        LG["LangGraph Agents<br/>(HTTP)"]
        DB["Databricks<br/>(HTTP via Unity Catalog)"]
    end

    subgraph Azure["Azure Cloud"]
        MCP["Neo4j MCP Server<br/>(Container Apps)"]
    end

    subgraph Neo4j["Graph Database"]
        N4J["Neo4j Aura<br/>or Self-Hosted"]
    end

    CD -->|MCP Protocol| MCP
    LG -->|HTTPS + API Key| MCP
    DB -->|HTTPS via Proxy| MCP
    MCP -->|Cypher Queries| N4J
```

---

## Neo4j MCP Server

The official Neo4j MCP server is a Go application that implements the Model Context Protocol, enabling AI agents to interact with Neo4j databases through a standardized interface.

### Core Architecture

```mermaid
graph TB
    subgraph Server["Neo4j MCP Server"]
        subgraph Transport["Transport Layer"]
            STDIO["STDIO Transport<br/>(stdin/stdout)"]
            HTTP["HTTP Transport<br/>(/mcp endpoint)"]
        end

        subgraph Middleware["HTTP Middleware Stack"]
            PATH["Path Validation<br/>(/mcp only)"]
            CORS["CORS Handler"]
            AUTH["Authentication<br/>(Bearer/Basic)"]
            LOG["Request Logging"]
        end

        subgraph Core["Core Components"]
            HANDLER["MCP Protocol Handler<br/>(JSON-RPC 2.0)"]
            TOOLS["Tool Registry"]
            DB["Database Service"]
        end

        subgraph Tools["Available Tools"]
            GS["get-schema"]
            RC["read-cypher"]
            WC["write-cypher"]
            GDS["list-gds-procedures"]
        end
    end

    HTTP --> PATH --> CORS --> AUTH --> LOG --> HANDLER
    STDIO --> HANDLER
    HANDLER --> TOOLS
    TOOLS --> GS & RC & WC & GDS
    GS & RC & WC & GDS --> DB
    DB -->|Neo4j Driver| NEO4J["Neo4j Database"]
```

### Available Tools

The MCP server exposes four tools for interacting with Neo4j:

| Tool | Description | Read-Only | Parameters |
|------|-------------|-----------|------------|
| `get-schema` | Retrieves database schema (labels, relationships, properties) | Yes | None |
| `read-cypher` | Executes read-only Cypher queries | Yes | `query`, `params` (optional) |
| `write-cypher` | Executes write Cypher queries (disabled in read-only mode) | No | `query`, `params` (optional) |
| `list-gds-procedures` | Lists available Graph Data Science procedures | Yes | None |

```mermaid
flowchart LR
    subgraph ReadOnly["Read-Only Mode (NEO4J_READ_ONLY=true)"]
        direction TB
        GS2["get-schema ✓"]
        RC2["read-cypher ✓"]
        WC2["write-cypher ✗<br/>(hidden)"]
        GDS2["list-gds-procedures ✓"]
    end

    subgraph Normal["Normal Mode"]
        direction TB
        GS1["get-schema ✓"]
        RC1["read-cypher ✓"]
        WC1["write-cypher ✓"]
        GDS1["list-gds-procedures ✓"]
    end
```

### Transport Modes

The server supports two transport modes:

```mermaid
graph TB
    subgraph STDIO["STDIO Transport"]
        S1["Client Process"]
        S2["stdin/stdout pipes"]
        S3["MCP Server Process"]
        S1 <-->|"JSON-RPC"| S2 <-->|"JSON-RPC"| S3
    end

    subgraph HTTP["HTTP Transport"]
        H1["Client"]
        H2["HTTPS"]
        H3["MCP Server<br/>POST /mcp"]
        H1 -->|"JSON-RPC Request"| H2 -->|"JSON-RPC Request"| H3
        H3 -->|"JSON-RPC Response"| H2 -->|"JSON-RPC Response"| H1
    end
```

| Aspect | STDIO | HTTP |
|--------|-------|------|
| Use Case | Desktop clients (Claude, VSCode) | Web clients, Multi-tenant |
| Credentials | Environment variables at startup | Per-request headers + env fallback |
| Startup Verification | Mandatory | Skipped if no env credentials |
| Multi-tenant | No | Yes |

### Authentication

```mermaid
sequenceDiagram
    participant Client
    participant AuthMiddleware
    participant MCPHandler
    participant Neo4j

    Client->>AuthMiddleware: POST /mcp (tools/call)

    alt Bearer Token Present
        AuthMiddleware->>AuthMiddleware: Extract Bearer token
        AuthMiddleware->>MCPHandler: Context with Bearer auth
        MCPHandler->>Neo4j: Query with Bearer auth
    else Basic Auth Present
        AuthMiddleware->>AuthMiddleware: Decode Basic credentials
        AuthMiddleware->>MCPHandler: Context with Basic auth
        MCPHandler->>Neo4j: Query with Basic auth
    else Environment Fallback
        AuthMiddleware->>MCPHandler: Context with env credentials
        MCPHandler->>Neo4j: Query with env credentials
    else No Credentials
        AuthMiddleware->>Client: 401 Unauthorized
    end

    Neo4j->>MCPHandler: Results
    MCPHandler->>Client: JSON-RPC Response
```

---

## Azure Deployment

### Resource Architecture

The deployment creates the following Azure resources:

```mermaid
graph TB
    subgraph RG["Resource Group"]
        subgraph Identity["Identity & Security"]
            MI["Managed Identity<br/>neo4jmcp-identity-{env}<br/><br/>Roles:<br/>• AcrPull<br/>• Key Vault Secrets User"]
            KV["Key Vault<br/>kv-{uniqueSuffix}<br/><br/>Secrets:<br/>• neo4j-uri<br/>• neo4j-username<br/>• neo4j-password<br/>• neo4j-database<br/>• mcp-api-key"]
        end

        subgraph Compute["Compute & Storage"]
            ACR["Container Registry<br/>neo4jmcpacr{suffix}<br/><br/>Images:<br/>• neo4j-mcp-server:latest<br/>• mcp-auth-proxy:latest"]
            CAE["Container Apps Environment<br/>neo4jmcp-env-{env}<br/><br/>• Consumption workload<br/>• Zone redundancy: off"]
            CA["Container App<br/>neo4jmcp-app-{env}<br/><br/>• 1 replica<br/>• External ingress (443)"]
        end

        subgraph Monitoring["Monitoring"]
            LA["Log Analytics<br/>neo4jmcp-logs-{env}<br/><br/>• 30-day retention<br/>• Container logs"]
        end
    end

    MI -->|Pull Images| ACR
    MI -->|Read Secrets| KV
    ACR -->|Host Images| CA
    KV -->|Inject Secrets| CA
    CA -->|Emit Logs| LA
    CAE -->|Host| CA
```

### Container Architecture

The Container App runs two sidecar containers:

```mermaid
graph TB
    subgraph Internet["Internet"]
        CLIENT["AI Client<br/>(Claude, LangGraph, etc.)"]
    end

    subgraph ACA["Azure Container Apps"]
        INGRESS["Ingress Controller<br/>HTTPS (443) → HTTP (8080)"]

        subgraph CA["Container App (1 replica)"]
            subgraph AuthProxy["Auth Proxy Container"]
                NX["Nginx + OpenResty<br/>Port 8080<br/><br/>Features:<br/>• API Key validation<br/>• Rate limiting (10 req/sec/IP)<br/>• Security headers<br/>• Health checks"]
            end

            subgraph MCPContainer["MCP Server Container"]
                MCP["Neo4j MCP Server<br/>Port 8000 (localhost only)<br/><br/>Features:<br/>• HTTP streaming transport<br/>• Read-only mode<br/>• JSON logging<br/>• Tool execution"]
            end
        end
    end

    subgraph External["External"]
        NEO4J["Neo4j Database<br/>(Aura/Self-hosted)"]
    end

    CLIENT -->|HTTPS + API Key| INGRESS
    INGRESS -->|HTTP| NX
    NX -->|localhost:8000| MCP
    MCP -->|Bolt Protocol| NEO4J
```

### Security Model

```mermaid
flowchart TB
    subgraph External["External Layer"]
        CLIENT["AI Client"]
    end

    subgraph EdgeSecurity["Edge Security (Auth Proxy)"]
        APIKEY["API Key Validation<br/>Bearer token or X-API-Key header"]
        RATE["Rate Limiting<br/>10 requests/second/IP"]
        HEADERS["Security Headers<br/>X-Content-Type-Options<br/>X-Frame-Options<br/>X-XSS-Protection"]
    end

    subgraph TransportSecurity["Transport Security"]
        TLS["TLS 1.2+<br/>Azure-managed certificates"]
        LOCALHOST["Internal Communication<br/>localhost only (127.0.0.1)"]
    end

    subgraph IdentitySecurity["Identity Security"]
        MI["Managed Identity<br/>No stored credentials"]
        KV["Key Vault<br/>RBAC authorization"]
    end

    subgraph DatabaseSecurity["Database Security"]
        READONLY["Read-Only Mode<br/>Server-level enforcement"]
        CLASSIFY["Query Classification<br/>EXPLAIN-based validation"]
    end

    CLIENT --> TLS --> APIKEY --> RATE --> HEADERS --> LOCALHOST --> MCP
    MI --> KV --> MCP
    MCP --> READONLY --> CLASSIFY --> NEO4J["Neo4j"]
```

**Security Layers:**

1. **Transport Security**: TLS 1.2+ enforced by Azure Container Apps
2. **API Authentication**: Bearer token or X-API-Key header validated by Nginx
3. **Rate Limiting**: 10 requests/second per IP (configurable)
4. **Request Protection**: 1MB max body, security headers
5. **Network Isolation**: MCP server listens only on localhost
6. **Secret Management**: Key Vault with RBAC, managed identity access
7. **Query Protection**: Read-only mode, EXPLAIN-based query classification

### Deployment Flow

```mermaid
sequenceDiagram
    participant User
    participant Script as deploy.sh
    participant Azure as Azure CLI
    participant Bicep
    participant Docker
    participant ACR
    participant CA as Container App

    User->>Script: ./scripts/deploy.sh

    Note over Script: Phase 1: Validation
    Script->>Script: Check Azure CLI auth
    Script->>Script: Validate .env file
    Script->>Script: Test Neo4j connectivity

    Note over Script,Bicep: Phase 2: Foundation Resources
    Script->>Azure: az deployment group create
    Azure->>Bicep: Deploy main.bicep
    Bicep->>Azure: Create Managed Identity
    Bicep->>Azure: Create Log Analytics
    Bicep->>Azure: Create Container Registry
    Bicep->>Azure: Create Key Vault + Secrets

    Note over Script,Docker: Phase 3: Build Images
    Script->>Docker: docker buildx build (MCP server)
    Script->>Docker: docker buildx build (Auth proxy)

    Note over Script,ACR: Phase 4: Push Images
    Script->>Docker: docker push (MCP server)
    Docker->>ACR: Upload image
    Script->>Docker: docker push (Auth proxy)
    Docker->>ACR: Upload image

    Note over Script,CA: Phase 5: Deploy App
    Script->>Azure: az deployment group create
    Azure->>Bicep: Deploy container-app.bicep
    Bicep->>CA: Create Container App
    CA->>ACR: Pull images
    CA->>CA: Start containers

    Note over Script: Phase 6: Generate Access
    Script->>Script: Create MCP_ACCESS.json
    Script->>User: Deployment complete!
```

---

## Databricks Extension

### Unity Catalog Integration

The architecture extends to Databricks through Unity Catalog HTTP connections:

```mermaid
graph TB
    subgraph Databricks["Databricks Workspace"]
        subgraph Notebooks["Compute"]
            NB["Notebooks / SQL"]
            AGENT["LangGraph Agent"]
        end

        subgraph UC["Unity Catalog"]
            CONN["HTTP Connection<br/>(neo4j_mcp)<br/><br/>• Is MCP: ✓<br/>• Bearer Token Auth"]
            SECRETS["Secrets Scope<br/>(mcp-neo4j-secrets)<br/><br/>• mcp_endpoint<br/>• mcp_api_key"]
        end

        subgraph Proxy["HTTP Proxy"]
            API["Databricks API<br/>/api/2.0/mcp/external/{conn}"]
        end
    end

    subgraph Azure["Azure"]
        MCP["Neo4j MCP Server<br/>(Container Apps)"]
    end

    subgraph Neo4j["Database"]
        N4J["Neo4j"]
    end

    NB -->|"http_request()"| CONN
    AGENT -->|"MCP tool call"| CONN
    CONN -->|credentials| SECRETS
    CONN --> API
    API -->|HTTPS + Bearer| MCP
    MCP -->|Cypher| N4J
```

### Request Flow Through Databricks

```mermaid
sequenceDiagram
    participant Notebook
    participant UC as Unity Catalog
    participant Proxy as Databricks Proxy
    participant MCP as Neo4j MCP Server
    participant Neo4j

    Notebook->>UC: http_request conn=neo4j_mcp
    UC->>UC: Resolve connection settings
    UC->>UC: Retrieve Bearer token from secrets
    UC->>Proxy: Forward request
    Proxy->>Proxy: Add Authorization header
    Proxy->>MCP: POST /mcp (JSON-RPC)

    MCP->>MCP: Validate API key
    MCP->>MCP: Parse JSON-RPC request

    alt get-schema
        MCP->>Neo4j: CALL apoc.meta.schema()
    else read-cypher
        MCP->>Neo4j: Execute Cypher query
    end

    Neo4j->>MCP: Query results
    MCP->>Proxy: JSON-RPC response
    Proxy->>UC: Forward response
    UC->>Notebook: Return results
```

### Agent Deployment

```mermaid
graph TB
    subgraph Development["Development"]
        CODE["Agent Code<br/>(neo4j_mcp_agent.py)"]
        NOTEBOOK["Deploy Notebook<br/>(neo4j-mcp-agent-deploy.ipynb)"]
    end

    subgraph MLflow["MLflow"]
        LOG["Log Model"]
        EVAL["Evaluate<br/>(AI scorers)"]
        REG["Register to<br/>Unity Catalog"]
    end

    subgraph Serving["Model Serving"]
        ENDPOINT["Serving Endpoint<br/>agents_mcp_demo_catalog-..."]
    end

    subgraph Runtime["Runtime"]
        UC["Unity Catalog<br/>HTTP Connection"]
        MCP["Neo4j MCP Server"]
    end

    CODE --> NOTEBOOK
    NOTEBOOK --> LOG --> EVAL --> REG --> ENDPOINT
    ENDPOINT -->|MCP tool calls| UC -->|HTTP| MCP
```

**Deployment Steps:**

1. **Test Agent**: Verify connectivity to Neo4j via MCP
2. **Log to MLflow**: Package as ResponsesAgent model
3. **Evaluate**: Run quality assessments with MLflow scorers
4. **Register**: Store in Unity Catalog for governance
5. **Deploy**: Create serving endpoint

---

## Request Flows

### Direct HTTP Client (LangGraph, Custom)

```mermaid
sequenceDiagram
    participant Client as AI Agent
    participant Nginx as Auth Proxy
    participant MCP as MCP Server
    participant Neo4j

    Client->>Nginx: POST /mcp<br/>Authorization: Bearer <api-key>

    Nginx->>Nginx: Validate API key

    alt Invalid/Missing Key
        Nginx->>Client: 401 Unauthorized
    else Valid Key
        Nginx->>MCP: Forward to localhost:8000

        MCP->>MCP: Parse JSON-RPC
        MCP->>MCP: Determine tool

        alt get-schema
            MCP->>Neo4j: CALL apoc.meta.schema()
            Neo4j->>MCP: Schema data
        else read-cypher
            MCP->>MCP: Classify query (EXPLAIN)
            alt Write Query Detected
                MCP->>Client: Error: Write not allowed
            else Read Query
                MCP->>Neo4j: Execute query
                Neo4j->>MCP: Results
            end
        end

        MCP->>Nginx: JSON-RPC response
        Nginx->>Client: Response with headers
    end
```

### MCP Protocol Messages

```mermaid
sequenceDiagram
    participant Client
    participant MCP as MCP Server

    Note over Client,MCP: Initialization
    Client->>MCP: initialize (protocolVersion, clientInfo)
    MCP->>Client: serverInfo, capabilities

    Note over Client,MCP: Tool Discovery
    Client->>MCP: tools/list
    MCP->>Client: [get-schema, read-cypher, ...]

    Note over Client,MCP: Tool Execution
    Client->>MCP: tools/call (name: "get-schema")
    MCP->>Client: Schema response

    Client->>MCP: tools/call (name: "read-cypher", query: "MATCH...")
    MCP->>Client: Query results
```

---

## Configuration Reference

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NEO4J_URI` | Yes (STDIO) | - | Neo4j connection URI |
| `NEO4J_USERNAME` | Yes (STDIO) | - | Database username |
| `NEO4J_PASSWORD` | Yes (STDIO) | - | Database password |
| `NEO4J_DATABASE` | No | `neo4j` | Target database |
| `NEO4J_READ_ONLY` | No | `false` | Enable read-only mode |
| `NEO4J_MCP_TRANSPORT` | No | `stdio` | Transport mode (`stdio`/`http`) |
| `NEO4J_MCP_HTTP_HOST` | No | `127.0.0.1` | HTTP bind address |
| `NEO4J_MCP_HTTP_PORT` | No | `80`/`443` | HTTP port |
| `NEO4J_LOG_FORMAT` | No | `text` | Log format (`text`/`json`) |
| `NEO4J_LOG_LEVEL` | No | `info` | Log verbosity |
| `MCP_API_KEY` | Yes | - | API key for auth proxy |

### Azure Resources

| Resource | SKU/Tier | Monthly Cost |
|----------|----------|--------------|
| Container Apps | Consumption (1 replica) | $15-30 |
| Container Registry | Basic | $5 |
| Key Vault | Standard | ~$0.50 |
| Log Analytics | PerGB2018 (30-day) | ~$2-5 |
| **Total** | | **~$25-40** |

---

## See Also

- [Main README](../README.md) - Quick start guide
- [Databricks Samples README](../databrick_samples/README.md) - Databricks integration guide
- [HTTP.md](../HTTP.md) - HTTP connection proposal
- [Neo4j MCP Server](https://github.com/neo4j/mcp) - Official repository
- [Model Context Protocol](https://modelcontextprotocol.io/) - MCP specification
