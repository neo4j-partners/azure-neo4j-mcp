# Databricks HTTP Connection for Neo4j MCP Server

## Problem Statement

Data scientists and analysts working in Databricks need to query Neo4j graph databases as part of their analytics workflows. Currently, connecting to the Neo4j MCP server from Databricks requires custom Python code and manual credential management, which creates several challenges:

- Credentials are often hardcoded in notebooks or stored insecurely
- Each user must write boilerplate code to establish connections
- There is no unified, SQL-friendly way to call MCP tools from Databricks
- Teams cannot leverage Databricks' native HTTP query federation capabilities

The impact is that graph data remains siloed, requiring extra engineering effort to integrate into Databricks-based analytics pipelines.

## Proposed Solution

Databricks introduced HTTP connections in Lakehouse Federation, which allows users to make authenticated HTTP requests to external APIs directly from SQL. By creating an HTTP connection to the Neo4j MCP server, users can:

- Query the MCP server's read-only tools (get-schema, read-cypher) using standard SQL syntax
- Store the MCP API key securely in Databricks secrets with Unity Catalog integration
- Share the connection across teams with proper access controls via Unity Catalog permissions

The solution consists of two components:

1. A Databricks notebook that creates the HTTP connection and demonstrates how to call MCP tools
2. A shell script that securely stores the MCP server credentials in Databricks secrets

This approach mirrors the existing pattern in the dbx-embedding-tests project, where secrets are managed via a setup script and consumed in notebooks via dbutils.secrets.get().

## How It Works

### Databricks HTTP Connections

Databricks HTTP connections are a feature of Lakehouse Federation that enable federated queries to external REST APIs. The connection stores:

- The base URL of the target server (the MCP server endpoint)
- Authentication credentials (bearer token stored as a secret reference)
- Connection metadata for Unity Catalog governance

Once created, the connection can be used with the http_request SQL function to make API calls.

### Bearer Token Authentication

The Neo4j MCP server deployed on Azure Container Apps uses bearer token authentication. Requests must include an Authorization header with the API key:

```
Authorization: Bearer <MCP_API_KEY>
```

Databricks HTTP connections support bearer token authentication natively. Rather than embedding the token in the connection definition, the connection references a Databricks secret, ensuring the token is never exposed in notebooks or logs.

### Secret Management

Databricks secrets provide secure storage for sensitive values. The approach is:

- Create a secret scope (a named container for secrets)
- Store the MCP API key and endpoint URL in the scope
- Reference the secrets in the HTTP connection using the secret() function
- Access is controlled via Unity Catalog permissions on the connection

## Requirements

### Functional Requirements

1. The notebook must create an HTTP connection in Unity Catalog that points to the Neo4j MCP server
2. The connection must use bearer token authentication with the token stored in Databricks secrets
3. The notebook must demonstrate calling the read-only MCP tools: get-schema and read-cypher
4. The notebook must include validation steps to verify the connection works correctly
5. The setup script must read credentials from a local environment file and push them to Databricks secrets
6. The setup script must validate that required credentials are present before attempting to create secrets
7. The setup script must work with the standard Databricks CLI

### Non-Functional Requirements

1. The setup script must not expose credentials in command history or logs
2. The notebook must be executable on Databricks Runtime 15.4 LTS or later, or SQL warehouses version 2023.40 or later
3. The solution must follow the existing patterns in the dbx-embedding-tests project for consistency
4. All secrets must be stored in a dedicated scope to avoid mixing with unrelated credentials

## Architecture

### Connection Flow

The data flow from Databricks to Neo4j follows this path:

1. User executes SQL with http_request function in a Databricks notebook or SQL warehouse
2. Databricks resolves the connection name and retrieves the bearer token from the secret scope
3. Databricks makes an HTTPS request to the MCP server endpoint with the bearer token in the Authorization header
4. The MCP server's auth proxy validates the API key
5. If valid, the request is forwarded to the MCP server which executes the requested tool
6. For read-cypher, the MCP server executes the read-only Cypher query against Neo4j
7. The response flows back through the same path to the Databricks notebook

### Components

| Component | Purpose |
|-----------|---------|
| setup_databricks_secrets.sh | Shell script to push MCP credentials to Databricks secrets |
| databricks_http_connection.ipynb | Databricks notebook to create connection and demonstrate usage |
| Secret scope (mcp-neo4j-secrets) | Databricks secret scope containing MCP_ENDPOINT and MCP_API_KEY |
| HTTP connection (neo4j_mcp) | Unity Catalog connection object for the MCP server |

### Secret Scope Contents

The secret scope will contain these secrets:

| Secret Key | Value | Description |
|------------|-------|-------------|
| endpoint | https://neo4j-mcp-xxxx.azurecontainerapps.io | The MCP server base URL |
| api_key | (generated during MCP server deployment) | The bearer token for authentication |

## Implementation Plan

### Phase 1: Analysis and Preparation - COMPLETED

- [x] Reviewed the existing setup_secrets.sh script in dbx-embedding-tests to understand the pattern
- [x] Reviewed the MCP_ACCESS.json file generated during MCP server deployment to understand available values
- [x] Confirmed the Databricks workspace requirements (Unity Catalog enabled, Runtime 15.4 LTS or later)
- [x] Determined the secret scope naming convention: mcp-neo4j-secrets (default)

**Analysis Findings:**

The MCP_ACCESS.json file contains the following relevant fields:
- endpoint: The base URL of the MCP server (e.g., https://neo4jmcp-app-dev.xxx.azurecontainerapps.io)
- api_key: The bearer token for authentication
- mcp_path: The path for MCP requests (typically "/mcp")

The setup_secrets.sh pattern from dbx-embedding-tests provides a solid foundation:
- Reads credentials from a local file
- Validates required values before proceeding
- Creates the secret scope if it does not exist
- Sets individual secrets using the Databricks CLI
- Lists created secrets for verification
- Prints usage instructions

### Phase 2: Create the Setup Script - COMPLETED

- [x] Created setup_databricks_secrets.sh following the pattern from dbx-embedding-tests
- [x] The script reads from the existing MCP_ACCESS.json file
- [x] The script validates that endpoint and api_key are present
- [x] The script creates the secret scope if it does not exist
- [x] The script sets each secret using the Databricks CLI
- [x] The script lists the created secrets for verification
- [x] The script prints usage instructions for both dbutils and HTTP connections

**Implemented Script:** scripts/setup_databricks_secrets.sh

The script stores four secrets in Databricks:
| Secret Key | Source | Description |
|------------|--------|-------------|
| endpoint | MCP_ACCESS.json endpoint | Base URL without path |
| api_key | MCP_ACCESS.json api_key | Bearer token for authentication |
| mcp_path | MCP_ACCESS.json mcp_path | The /mcp path |
| mcp_url | endpoint + mcp_path | Full URL for convenience |

### Phase 3: Create the Databricks Notebook - COMPLETED

- [x] Created databricks_http_connection.ipynb as a Databricks notebook
- [x] The notebook includes markdown cells explaining the purpose and prerequisites
- [x] The notebook retrieves secret values to validate they exist
- [x] The notebook creates the HTTP connection using SQL with secret references
- [x] The notebook demonstrates calling get-schema to retrieve the Neo4j database schema
- [x] The notebook demonstrates calling read-cypher with a sample query
- [x] The notebook includes error handling guidance for common issues
- [x] The notebook includes cleanup instructions to drop the connection if needed
- [x] Added reusable `query_neo4j()` helper function

**Implemented Notebook:** databrick_samples/neo4j-mcp-http-connection.ipynb

The notebook provides:
- Step-by-step setup with validation
- SQL cells using `%%sql` magic for HTTP connection creation
- MCP JSON-RPC examples for tools/list, get-schema, and read-cypher
- Helper function for easy reuse in other notebooks
- Troubleshooting guide for common issues

### Phase 4: Documentation and Integration - COMPLETED

- [x] Added README.md to databrick_samples directory with full documentation
- [x] Updated main README.md to reference databrick_samples and HTTP.md
- [x] Documented prerequisites (Unity Catalog, runtime version, Databricks CLI)
- [x] Documented the two-step setup process (run script, then notebook)

**Implemented Files:**
- databrick_samples/README.md - Comprehensive documentation for Databricks integration
- README.md - Updated Documentation section with new references

### Phase 5: Verification

- Test the setup script against a real Databricks workspace
- Verify secrets are created correctly using databricks secrets list-secrets
- Test the notebook on Databricks Runtime 15.4 LTS
- Verify the read-only MCP tools (get-schema, read-cypher) can be called successfully
- Confirm the bearer token is not exposed in any logs or outputs
- Validate that connection permissions work as expected in Unity Catalog

## Files to Create

| File | Location | Purpose | Status |
|------|----------|---------|--------|
| setup_databricks_secrets.sh | scripts/ | Shell script to configure Databricks secrets | COMPLETED |
| neo4j-mcp-http-connection.ipynb | databrick_samples/ | Notebook to create and test HTTP connection | COMPLETED |
| README.md | databrick_samples/ | Documentation for Databricks integration | COMPLETED |

## Dependencies

### External Dependencies

- Databricks CLI must be installed and authenticated
- Databricks workspace must have Unity Catalog enabled
- Compute must be Databricks Runtime 15.4 LTS or later, or SQL warehouse 2023.40 or later
- The MCP server must be deployed and accessible from Databricks (public endpoint)

### Project Dependencies

- MCP_ACCESS.json must exist (generated by deploy.sh)
- The MCP server must be running and accepting requests

## Risks and Mitigations

### Risk: HTTP connections feature not available

HTTP connections in Lakehouse Federation are currently in Public Preview. If a workspace does not have this feature enabled, the notebook will fail.

Mitigation: Document the feature requirements clearly. Provide a fallback approach using Python SDK for workspaces without HTTP connections.

### Risk: Network connectivity

The MCP server runs on Azure Container Apps with a public endpoint. Databricks must be able to reach this endpoint.

Mitigation: Document that the MCP server endpoint must be publicly accessible. For private deployments, note that VNet integration would be required.

### Risk: Secret scope limits

Databricks has limits on the number of secret scopes and secrets per workspace.

Mitigation: Use a single dedicated scope for MCP credentials rather than creating per-user scopes.

## Security Policy: Read-Only Access

This integration is intentionally restricted to read-only operations. Write access to the Neo4j database via the MCP server is not permitted through this Databricks connection.

Rationale:
- Databricks users should query graph data for analytics, not modify production graph structures
- Write operations require additional governance and approval workflows
- Read-only access reduces the risk of accidental data corruption or deletion
- Graph schema changes should go through dedicated change management processes

The write-cypher tool is explicitly excluded from this integration. If write access is required for a specific use case, it should be requested through a separate approval process with appropriate safeguards.

## Success Criteria

The implementation is complete when:

1. The setup script successfully creates secrets in Databricks without exposing credentials
2. The notebook creates an HTTP connection that authenticates with the MCP server
3. Users can call get-schema and receive the Neo4j database schema
4. Users can call read-cypher with a Cypher query and receive results
5. The bearer token never appears in notebook outputs, logs, or command history
6. The solution follows the patterns established in dbx-embedding-tests
7. Write operations are not exposed or documented as available functionality

## Implementation Progress

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1: Analysis and Preparation | COMPLETED | Reviewed patterns, confirmed requirements |
| Phase 2: Create Setup Script | COMPLETED | scripts/setup_databricks_secrets.sh created |
| Phase 3: Create Databricks Notebook | COMPLETED | databrick_samples/neo4j-mcp-http-connection.ipynb created |
| Phase 4: Documentation and Integration | COMPLETED | README.md added, main README updated |
| Phase 5: Verification | Pending | Testing against real Databricks workspace |

## Next Steps

Remaining work to complete this proposal:

1. ~~Create the setup_databricks_secrets.sh script~~ DONE
2. ~~Create the neo4j-mcp-http-connection.ipynb notebook~~ DONE
3. Test against a Databricks workspace with the deployed MCP server
4. ~~Update project documentation~~ DONE
5. ~~Add to databrick_samples directory with README~~ DONE
