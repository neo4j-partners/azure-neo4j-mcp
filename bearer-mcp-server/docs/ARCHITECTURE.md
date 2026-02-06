# System Architecture

> **Disclaimer:** This is a **sample template** provided as-is for demonstration and learning purposes. It is not officially supported and requires full security hardening and review before any production use.

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AZURE INFRASTRUCTURE                                      │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                         AZURE CONTAINER APPS ENVIRONMENT                             │   │
│  │                                                                                      │   │
│  │   ┌────────────────────────────────────────────────────────────────────────────┐    │   │
│  │   │                       NEO4J MCP SERVER CONTAINER                           │    │   │
│  │   │                           (Port 8000, HTTPS)                               │    │   │
│  │   │                                                                            │    │   │
│  │   │   ┌──────────────────┐    ┌─────────────────┐    ┌──────────────────┐     │    │   │
│  │   │   │  MCP Protocol    │    │ Bearer Token    │    │  Neo4j Python    │     │    │   │
│  │   │   │  Handler         │───▶│ Extractor       │───▶│  Driver          │     │    │   │
│  │   │   │  (JSON-RPC 2.0)  │    │                 │    │  (BearerAuth)    │     │    │   │
│  │   │   └──────────────────┘    └─────────────────┘    └────────┬─────────┘     │    │   │
│  │   │                                                           │               │    │   │
│  │   └───────────────────────────────────────────────────────────┼───────────────┘    │   │
│  │                                                               │                    │   │
│  └───────────────────────────────────────────────────────────────┼────────────────────┘   │
│                                                                  │                        │
│  ┌───────────────────────┐   ┌───────────────────────┐          │                        │
│  │  KEY VAULT            │   │  LOG ANALYTICS        │          │                        │
│  │  (Minimal Secrets)    │   │  WORKSPACE            │          │                        │
│  │                       │   │                       │          │                        │
│  │  • neo4j-uri          │   │  • Container logs     │          │                        │
│  │  • neo4j-database     │   │  • Telemetry          │          │                        │
│  │  (NO credentials)     │   │                       │          │                        │
│  └───────────────────────┘   └───────────────────────┘          │                        │
│                                                                  │                        │
└──────────────────────────────────────────────────────────────────┼────────────────────────┘
                                                                   │
                                                                   │ Bearer Token
                                                                   │ (JWT passed through)
                                                                   │
                                                                   ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              NEO4J ENTERPRISE (OIDC-ENABLED)                                 │
│                           (Deployed via azure-ee-template or self-hosted)                   │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   ┌───────────────────────────────────────────────────────────────────────────────────┐    │
│   │                            OIDC AUTHENTICATION PROVIDER                            │    │
│   │                                                                                    │    │
│   │   Token Received ──▶ Validate against IdP JWKS ──▶ Extract Claims ──▶ Map Roles   │    │
│   │                                                                                    │    │
│   │   neo4j.conf:                                                                      │    │
│   │   ├── dbms.security.authentication_providers=oidc-m2m,native                       │    │
│   │   ├── dbms.security.oidc.m2m.well_known_discovery_uri=https://login.microsoft...   │    │
│   │   └── dbms.security.oidc.m2m.authorization.group_to_role_mapping=...               │    │
│   │                                                                                    │    │
│   └───────────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                             │
│   ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────────────┐     │
│   │  QUERY EXECUTION    │   │  ROLE-BASED ACCESS  │   │  AUDIT LOGGING               │     │
│   │                     │   │                     │   │                              │     │
│   │  Cypher queries run │   │  Neo4j.Admin=admin  │   │  Every query attributed     │     │
│   │  with user identity │   │  Neo4j.ReadWrite=   │   │  to actual user identity    │     │
│   │                     │   │       editor        │   │  from JWT claims            │     │
│   │                     │   │  Neo4j.ReadOnly=    │   │                              │     │
│   │                     │   │       reader        │   │                              │     │
│   └─────────────────────┘   └─────────────────────┘   └─────────────────────────────┘     │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              IDENTITY PROVIDER (Microsoft Entra ID)                          │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   ┌───────────────────────────────────────┐   ┌───────────────────────────────────────┐    │
│   │  API APP REGISTRATION                  │   │  CLIENT APP REGISTRATION              │    │
│   │  (Neo4j as Resource)                   │   │  (Your Application)                   │    │
│   │                                        │   │                                       │    │
│   │  • Audience: api://neo4j-m2m           │   │  • Client ID: {guid}                  │    │
│   │  • App Roles:                          │   │  • Client Secret: ******              │    │
│   │    - Neo4j.Admin                       │   │  • API Permissions:                   │    │
│   │    - Neo4j.ReadWrite                   │   │    - Neo4j.Admin (or other role)      │    │
│   │    - Neo4j.ReadOnly                    │   │                                       │    │
│   │                                        │   │                                       │    │
│   └───────────────────────────────────────┘   └───────────────────────────────────────┘    │
│                                                                                             │
│                                         │                                                   │
│                                         │ OAuth 2.0 Client Credentials Flow                │
│                                         ▼                                                   │
│                              ┌─────────────────────┐                                       │
│                              │  TOKEN ENDPOINT     │                                       │
│                              │                     │                                       │
│                              │  POST /oauth2/v2.0/ │                                       │
│                              │       token         │                                       │
│                              │                     │                                       │
│                              │  Returns: JWT with  │                                       │
│                              │  - aud (audience)   │                                       │
│                              │  - roles (claims)   │                                       │
│                              │  - exp (expiry)     │                                       │
│                              └─────────────────────┘                                       │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       CLIENT APPLICATIONS                                    │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                             │
│   ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────────────┐     │
│   │  AI AGENTS          │   │  LLM APPLICATIONS   │   │  AUTOMATION TOOLS            │     │
│   │                     │   │                     │   │                              │     │
│   │  • Claude Code      │   │  • Custom RAG apps  │   │  • CI/CD pipelines           │     │
│   │  • Cursor           │   │  • LangChain        │   │  • Data ingestion            │     │
│   │  • Windsurf         │   │  • LlamaIndex       │   │  • Scheduled jobs            │     │
│   │  • VS Code Copilot  │   │                     │   │                              │     │
│   └─────────────────────┘   └─────────────────────┘   └─────────────────────────────┘     │
│                                                                                             │
│   Authentication Flow:                                                                      │
│   ┌───────────────────────────────────────────────────────────────────────────────────┐    │
│   │                                                                                    │    │
│   │   1. Acquire Token    2. Call MCP Server      3. Query Execution                   │    │
│   │                                                                                    │    │
│   │   Client ──────────▶ Entra ID ──────────▶ JWT Token                                │    │
│   │                                              │                                     │    │
│   │                                              ▼                                     │    │
│   │   Client ──────────▶ MCP Server ──────────▶ Neo4j ──────────▶ Results             │    │
│   │   POST /mcp         Authorization:          BearerAuth                             │    │
│   │   (JSON-RPC)        Bearer <jwt>            validates token                        │    │
│   │                                                                                    │    │
│   └───────────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Summary

```
┌────────────┐     ┌───────────┐     ┌───────────────┐     ┌──────────────┐     ┌─────────┐
│   Client   │────▶│ Entra ID  │────▶│  MCP Server   │────▶│ Neo4j (OIDC) │────▶│ Results │
│            │     │           │     │  (Azure CA)   │     │              │     │         │
│ 1. Request │     │ 2. Issue  │     │ 3. Extract &  │     │ 4. Validate  │     │ 6. Data │
│    Token   │     │    JWT    │     │    Forward    │     │    Token &   │     │         │
│            │◀────│           │     │    Token      │     │    Execute   │────▶│ 5. Audit│
└────────────┘     └───────────┘     └───────────────┘     └──────────────┘     └─────────┘
```
