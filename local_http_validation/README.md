# Local HTTP Mode Validation

Tests whether the official Docker Hub Neo4j MCP server image (`mcp/neo4j`) supports HTTP transport mode with bearer token authentication.

## How HTTP Mode Authentication Works

**Important:** In HTTP mode, the MCP server does NOT use `NEO4J_USERNAME`/`NEO4J_PASSWORD` environment variables.

Instead, authentication is **per-request** via HTTP headers:
- `Authorization: Bearer <jwt-token>` - For SSO/OIDC with Neo4j Enterprise
- `Authorization: Basic <base64>` - For username/password

The MCP server extracts credentials from the request and passes them directly to Neo4j for validation. The server itself is just a passthrough.

```
Client Request                    MCP Server                      Neo4j
     │                                │                              │
     │ Authorization: Bearer <jwt>    │                              │
     ├───────────────────────────────>│                              │
     │                                │  neo4j.BearerAuth(jwt)       │
     │                                ├─────────────────────────────>│
     │                                │                              │
     │                                │  Validate against OIDC       │
     │                                │<─────────────────────────────┤
     │                                │                              │
     │  Response                      │                              │
     │<───────────────────────────────┤                              │
```

## Prerequisites

- Docker installed and running
- [uv](https://github.com/astral-sh/uv) installed (`brew install uv` or `pip install uv`)
- (Optional) A running Neo4j instance for full validation

## Quick Start

### 1. Start the MCP Server in HTTP Mode

```bash
cd local_http_validation

# Configure Neo4j URI (optional - defaults to host.docker.internal:7687)
cp .env.sample .env
# Edit NEO4J_URI if needed

# Start the container
./scripts/start-server.sh
```

### 2. Test HTTP Mode (No Neo4j Required)

```bash
# Just verify HTTP mode is enabled
./scripts/test.sh --http-only
```

### 3. Test with Credentials

```bash
# Test with bearer token (for SSO/OIDC)
uv run test_http_mode.py --bearer-token "eyJhbGc..."

# Test with basic auth (username/password)
uv run test_http_mode.py --username neo4j --password secret
```

### 4. Stop the Server

```bash
./scripts/stop-server.sh
```

## Test Options

```bash
# HTTP mode only (no Neo4j needed)
uv run test_http_mode.py --http-only

# Bearer token - direct JWT
uv run test_http_mode.py --bearer-token "eyJhbGciOiJSUzI1NiIs..."

# Bearer token - Azure Entra ID (automatic token acquisition)
uv run test_http_mode.py \
  --azure-tenant-id "your-tenant-id" \
  --azure-client-id "your-client-id" \
  --azure-client-secret "your-secret"

# Bearer token - Azure with custom audience
uv run test_http_mode.py \
  --azure-tenant-id "..." \
  --azure-client-id "..." \
  --azure-client-secret "..." \
  --azure-audience "api://neo4j-m2m"

# Basic authentication
uv run test_http_mode.py --username neo4j --password yourpassword

# Custom endpoint
uv run test_http_mode.py --endpoint http://localhost:9000
```

## Bearer Token Testing

To test bearer token authentication, first set up `bearer-mcp-server/` following its [README](../bearer-mcp-server/README.md), then copy the `.env` file:

```bash
# From the local_http_validation directory
cp ../bearer-mcp-server/.env .env

# Run the test - Azure token acquired automatically!
uv run test_http_mode.py
```

The test script reads the same environment variables:
- `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_AUDIENCE`

## What Gets Tested

| Test | Description | Requires Neo4j |
|------|-------------|----------------|
| HTTP Health Check | Server responds on HTTP port | No |
| No Auth (401) | Server rejects unauthenticated requests | No |
| Bearer Token | Server accepts Bearer format, passes to Neo4j | No* |
| Basic Auth | Server accepts Basic format, passes to Neo4j | No* |
| MCP Initialize | Protocol initialization | Yes |
| List Tools | Enumerate available tools | Yes |
| Get Schema | Execute get-schema tool | Yes |

*These tests verify the MCP server accepts the auth format. Actual validation happens at Neo4j.

## Expected Output

### HTTP Mode Works (No Neo4j)

```
============================================================
Neo4j MCP Server - HTTP Mode Validation
============================================================
INFO Endpoint: http://localhost:8080
INFO Auth mode: None provided
INFO HTTP-only mode: True

INFO NOTE: In HTTP mode, auth is per-request via Authorization header.
INFO The MCP server passes credentials directly to Neo4j for validation.

TEST 1. HTTP Mode Health Check
PASS Server is responding on HTTP - HTTP mode is ENABLED

TEST 2. Request Without Authentication
PASS Server correctly requires authentication (HTTP 401)
INFO Server advertises Bearer token support
INFO Server advertises Basic auth support

...

============================================================
Test Results Summary
============================================================

Passed: 2, Failed: 0, Skipped: 5, Total: 7
PASS All tests passed! HTTP mode is functional.
```

### With Valid Bearer Token

```
TEST 3. Bearer Token Authentication
INFO Testing with token: eyJhbGciOi...last10chars
PASS Bearer token accepted - Neo4j validated the token!
INFO Tools returned: 4
```

### With Invalid Bearer Token

```
TEST 3. Bearer Token Authentication
INFO Testing with token: invalid-to...ken-here
PASS Bearer token FORMAT accepted by MCP server
WARN Neo4j rejected the token (expected if token is invalid/expired)
INFO This confirms the MCP server passes bearer tokens to Neo4j
```

## Troubleshooting

### Server Won't Start

```bash
docker logs neo4j-mcp-http-test
```

### Connection Refused

The image might not support HTTP mode. Check the logs for errors.

### 401 on All Requests

This is expected! It means HTTP mode is working. The MCP server requires authentication on every request - credentials are passed to Neo4j for validation.

## Files

| File | Purpose |
|------|---------|
| `test_http_mode.py` | Main validation script (PEP 723, runs with `uv run`) |
| `scripts/start-server.sh` | Start Docker container in HTTP mode |
| `scripts/stop-server.sh` | Stop and remove container |
| `scripts/test.sh` | Convenience wrapper |
| `.env.sample` | Configuration template |
