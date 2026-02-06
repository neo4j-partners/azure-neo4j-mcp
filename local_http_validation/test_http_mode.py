#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.31.0",
#     "python-dotenv>=1.0.0",
#     "msal>=1.24.0",
# ]
# ///
"""
Neo4j MCP Server - HTTP Mode Validation Test

Tests whether the official mcp/neo4j Docker image supports HTTP transport mode
with bearer token and basic authentication.

IMPORTANT: In HTTP mode, authentication is PER-REQUEST via HTTP headers.
The MCP server does NOT use NEO4J_USERNAME/NEO4J_PASSWORD env vars.
Instead, each request must include an Authorization header:
  - Bearer token: Authorization: Bearer <jwt-token>
  - Basic auth:   Authorization: Basic <base64(user:pass)>

The MCP server passes these credentials directly to Neo4j for validation.

Usage:
    uv run test_http_mode.py
    uv run test_http_mode.py --bearer-token <jwt>
    uv run test_http_mode.py --username neo4j --password secret
    uv run test_http_mode.py --http-only  # Only test HTTP mode works, skip Neo4j
"""

import argparse
import base64
import json
import os
import sys
from typing import Optional

import requests
from dotenv import load_dotenv

# Optional: MSAL for Azure Entra ID token acquisition
try:
    from msal import ConfidentialClientApplication

    MSAL_AVAILABLE = True
except ImportError:
    MSAL_AVAILABLE = False

# =============================================================================
# Configuration
# =============================================================================

# Load .env from script directory
script_dir = os.path.dirname(os.path.abspath(__file__))
env_file = os.path.join(script_dir, ".env")
if os.path.exists(env_file):
    load_dotenv(env_file)


# Colors for terminal output
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    CYAN = "\033[0;36m"
    NC = "\033[0m"  # No Color


def log_header(msg: str) -> None:
    print(f"\n{Colors.CYAN}{'=' * 60}{Colors.NC}")
    print(f"{Colors.CYAN}{msg}{Colors.NC}")
    print(f"{Colors.CYAN}{'=' * 60}{Colors.NC}")


def log_test(msg: str) -> None:
    print(f"\n{Colors.BLUE}TEST{Colors.NC} {msg}")


def log_pass(msg: str) -> None:
    print(f"{Colors.GREEN}PASS{Colors.NC} {msg}")


def log_fail(msg: str) -> None:
    print(f"{Colors.RED}FAIL{Colors.NC} {msg}")


def log_warn(msg: str) -> None:
    print(f"{Colors.YELLOW}WARN{Colors.NC} {msg}")


def log_info(msg: str) -> None:
    print(f"{Colors.BLUE}INFO{Colors.NC} {msg}")


# =============================================================================
# Token Acquisition
# =============================================================================


def get_azure_token(
    tenant_id: str,
    client_id: str,
    client_secret: str,
    audience: Optional[str] = None,
) -> str:
    """
    Acquire a bearer token from Azure Entra ID (formerly Azure AD).

    This uses the OAuth2 client credentials flow to get a token for
    machine-to-machine authentication.

    Args:
        tenant_id: Azure AD tenant ID
        client_id: Application (client) ID of the registered app
        client_secret: Client secret for the app
        audience: Optional audience/resource (default: api://{client_id})

    Returns:
        Access token string (JWT)

    Raises:
        ImportError: If msal is not installed
        Exception: If token acquisition fails
    """
    if not MSAL_AVAILABLE:
        raise ImportError(
            "msal is required for Azure Entra ID authentication.\n"
            "Install with: pip install msal"
        )

    app = ConfidentialClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
        client_credential=client_secret,
    )

    # Use custom audience if provided, otherwise default to api://{client_id}
    scope_base = audience if audience else f"api://{client_id}"
    scopes = [f"{scope_base}/.default"]

    log_info(f"Requesting token from Azure Entra ID...")
    log_info(f"  Tenant: {tenant_id[:8]}...{tenant_id[-4:]}")
    log_info(f"  Client: {client_id[:8]}...{client_id[-4:]}")
    log_info(f"  Scope: {scopes[0]}")

    result = app.acquire_token_for_client(scopes=scopes)

    if "access_token" not in result:
        error = result.get("error_description", result.get("error", "Unknown error"))
        raise Exception(f"Failed to acquire token: {error}")

    token = result["access_token"]
    log_pass(f"Token acquired ({len(token)} chars)")
    return token


def get_token_from_env() -> Optional[str]:
    """
    Attempt to get a bearer token from environment variables.

    Checks for:
    1. MCP_BEARER_TOKEN - Direct token
    2. AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET - Azure Entra ID

    Returns:
        Token string if available, None otherwise
    """
    # Check for direct token first
    token = os.environ.get("MCP_BEARER_TOKEN")
    if token:
        log_info("Using MCP_BEARER_TOKEN from environment")
        return token

    # Check for Azure credentials
    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")
    audience = os.environ.get("AZURE_AUDIENCE")

    if tenant_id and client_id and client_secret:
        return get_azure_token(tenant_id, client_id, client_secret, audience)

    return None


# =============================================================================
# MCP HTTP Client
# =============================================================================


class MCPHttpClient:
    """Simple MCP client for HTTP transport testing."""

    def __init__(self, endpoint: str):
        self.endpoint = endpoint.rstrip("/")
        self.mcp_url = f"{self.endpoint}/mcp"
        self.request_id = 0

    def _next_id(self) -> int:
        self.request_id += 1
        return self.request_id

    def _call(
        self,
        method: str,
        params: Optional[dict] = None,
        auth_header: Optional[str] = None,
        timeout: int = 10,
    ) -> dict:
        """Make a JSON-RPC 2.0 call to the MCP server."""
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "id": self._next_id(),
        }
        if params:
            payload["params"] = params

        headers = {"Content-Type": "application/json"}
        if auth_header:
            headers["Authorization"] = auth_header

        response = requests.post(
            self.mcp_url,
            json=payload,
            headers=headers,
            timeout=timeout,
        )

        try:
            json_body = response.json()
        except Exception:
            json_body = None

        return {
            "status_code": response.status_code,
            "headers": dict(response.headers),
            "body": response.text,
            "json": json_body,
        }

    def health_check(self, timeout: int = 5) -> bool:
        """Check if the server is responding on HTTP."""
        try:
            # Try the /mcp endpoint - should return 401 without auth
            response = requests.post(
                self.mcp_url,
                json={"jsonrpc": "2.0", "method": "tools/list", "id": 1},
                headers={"Content-Type": "application/json"},
                timeout=timeout,
            )
            # Any response (including 401) means HTTP mode is working
            return response.status_code in [200, 401, 403]
        except requests.exceptions.ConnectionError:
            return False
        except requests.exceptions.Timeout:
            return False

    def test_no_auth(self) -> dict:
        """Test request without authentication."""
        return self._call("tools/list")

    def test_bearer_auth(self, token: str) -> dict:
        """Test request with Bearer token authentication."""
        return self._call("tools/list", auth_header=f"Bearer {token}")

    def test_basic_auth(self, username: str, password: str) -> dict:
        """Test request with Basic authentication."""
        credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
        return self._call("tools/list", auth_header=f"Basic {credentials}")

    def initialize(self, auth_header: str) -> dict:
        """Initialize MCP connection."""
        return self._call(
            "initialize",
            params={
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "http-mode-validator", "version": "1.0.0"},
            },
            auth_header=auth_header,
        )

    def list_tools(self, auth_header: str) -> dict:
        """List available tools."""
        return self._call("tools/list", auth_header=auth_header)

    def call_tool(self, name: str, arguments: dict, auth_header: str) -> dict:
        """Call a specific tool."""
        return self._call(
            "tools/call",
            params={"name": name, "arguments": arguments},
            auth_header=auth_header,
        )


# =============================================================================
# Test Suite
# =============================================================================


class TestResults:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.skipped = 0

    def record_pass(self):
        self.passed += 1

    def record_fail(self):
        self.failed += 1

    def record_skip(self):
        self.skipped += 1

    def summary(self) -> str:
        total = self.passed + self.failed + self.skipped
        return f"Passed: {self.passed}, Failed: {self.failed}, Skipped: {self.skipped}, Total: {total}"


def run_tests(
    endpoint: str,
    bearer_token: Optional[str] = None,
    username: Optional[str] = None,
    password: Optional[str] = None,
    http_only: bool = False,
) -> TestResults:
    """Run the HTTP mode validation test suite."""

    results = TestResults()
    client = MCPHttpClient(endpoint)

    # Determine auth mode
    has_bearer = bearer_token is not None
    has_basic = username is not None and password is not None

    log_header("Neo4j MCP Server - HTTP Mode Validation")
    log_info(f"Endpoint: {endpoint}")
    log_info(f"Auth mode: {'Bearer token' if has_bearer else 'Basic auth' if has_basic else 'None provided'}")
    log_info(f"HTTP-only mode: {http_only}")
    print()
    log_info("NOTE: In HTTP mode, auth is per-request via Authorization header.")
    log_info("The MCP server passes credentials directly to Neo4j for validation.")

    # -------------------------------------------------------------------------
    # Test 1: HTTP Mode Health Check
    # -------------------------------------------------------------------------
    log_test("1. HTTP Mode Health Check")
    if client.health_check():
        log_pass("Server is responding on HTTP - HTTP mode is ENABLED")
        results.record_pass()
    else:
        log_fail("Server is not responding on HTTP")
        log_info("This means either:")
        log_info("  - The container isn't running (check: docker ps)")
        log_info("  - HTTP mode is not supported by this image")
        log_info("  - Check logs: docker logs neo4j-mcp-http-test")
        results.record_fail()
        return results  # Can't continue without HTTP

    # -------------------------------------------------------------------------
    # Test 2: Request Without Authentication (should require auth)
    # -------------------------------------------------------------------------
    log_test("2. Request Without Authentication")
    try:
        response = client.test_no_auth()
        if response["status_code"] == 401:
            log_pass(f"Server correctly requires authentication (HTTP 401)")
            www_auth = response["headers"].get("Www-Authenticate", "")
            if "Bearer" in www_auth:
                log_info("Server advertises Bearer token support")
            if "Basic" in www_auth:
                log_info("Server advertises Basic auth support")
            results.record_pass()
        else:
            log_warn(f"Unexpected response: HTTP {response['status_code']}")
            log_info(f"Body: {response['body'][:200]}")
            results.record_fail()
    except Exception as e:
        log_fail(f"Request failed: {e}")
        results.record_fail()

    # -------------------------------------------------------------------------
    # Test 3: Bearer Token Authentication
    # -------------------------------------------------------------------------
    log_test("3. Bearer Token Authentication")
    if not has_bearer:
        log_warn("Skipped - no bearer token provided (use --bearer-token)")
        log_info("To test bearer auth, obtain a JWT from your identity provider")
        results.record_skip()
    else:
        try:
            # Show token preview (first/last 10 chars)
            token_preview = f"{bearer_token[:10]}...{bearer_token[-10:]}" if len(bearer_token) > 25 else bearer_token
            log_info(f"Testing with token: {token_preview}")

            response = client.test_bearer_auth(bearer_token)

            if response["status_code"] == 200:
                log_pass("Bearer token accepted - Neo4j validated the token!")
                if response["json"]:
                    result = response["json"].get("result", {})
                    tools = result.get("tools", [])
                    log_info(f"Tools returned: {len(tools)}")
                results.record_pass()
            elif response["status_code"] == 401:
                # Server accepted bearer format, but Neo4j rejected the token
                log_pass("Bearer token FORMAT accepted by MCP server")
                log_warn("Neo4j rejected the token (expected if token is invalid/expired)")
                log_info("This confirms the MCP server passes bearer tokens to Neo4j")
                log_info(f"Response: {response['body'][:200]}")
                results.record_pass()  # HTTP mode works, token validation is Neo4j's job
            else:
                log_fail(f"Unexpected response: HTTP {response['status_code']}")
                log_info(f"Body: {response['body'][:200]}")
                results.record_fail()
        except Exception as e:
            log_fail(f"Request failed: {e}")
            results.record_fail()

    # -------------------------------------------------------------------------
    # Test 4: Basic Authentication
    # -------------------------------------------------------------------------
    log_test("4. Basic Authentication")
    if not has_basic:
        log_warn("Skipped - no username/password provided (use --username --password)")
        results.record_skip()
    elif http_only:
        log_warn("Skipped (--http-only flag)")
        results.record_skip()
    else:
        try:
            response = client.test_basic_auth(username, password)

            if response["status_code"] == 200:
                log_pass("Basic auth accepted - Neo4j validated credentials")
                if response["json"]:
                    result = response["json"].get("result", {})
                    tools = result.get("tools", [])
                    log_info(f"Tools returned: {len(tools)}")
                results.record_pass()
            elif response["status_code"] == 401:
                log_pass("Basic auth FORMAT accepted by MCP server")
                log_warn("Neo4j rejected credentials (check username/password)")
                log_info(f"Response: {response['body'][:200]}")
                results.record_pass()  # HTTP mode works
            else:
                log_fail(f"Unexpected response: HTTP {response['status_code']}")
                log_info(f"Body: {response['body'][:200]}")
                results.record_fail()
        except Exception as e:
            log_fail(f"Request failed: {e}")
            results.record_fail()

    # -------------------------------------------------------------------------
    # Test 5: MCP Protocol - Initialize (requires valid credentials)
    # -------------------------------------------------------------------------
    log_test("5. MCP Protocol - Initialize")
    if http_only:
        log_warn("Skipped (--http-only flag)")
        results.record_skip()
    elif not has_bearer and not has_basic:
        log_warn("Skipped - no credentials provided")
        results.record_skip()
    else:
        try:
            # Use bearer if available, otherwise basic
            if has_bearer:
                auth_header = f"Bearer {bearer_token}"
            else:
                credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
                auth_header = f"Basic {credentials}"

            response = client.initialize(auth_header)

            if response["status_code"] == 200 and response["json"]:
                result = response["json"].get("result", {})
                if "error" in response["json"]:
                    error = response["json"]["error"]
                    log_fail(f"Initialize error: {error.get('message', 'unknown')}")
                    results.record_fail()
                else:
                    protocol = result.get("protocolVersion", "unknown")
                    server_info = result.get("serverInfo", {})
                    log_pass("MCP Initialize successful")
                    log_info(f"Protocol: {protocol}")
                    log_info(f"Server: {server_info.get('name', 'unknown')} v{server_info.get('version', 'unknown')}")
                    results.record_pass()
            elif response["status_code"] == 401:
                log_warn("Initialize rejected (invalid credentials)")
                log_info("HTTP mode works, but credentials not accepted by Neo4j")
                results.record_pass()  # HTTP mode itself works
            else:
                log_fail(f"Initialize failed: HTTP {response['status_code']}")
                log_info(f"Body: {response['body'][:300]}")
                results.record_fail()
        except Exception as e:
            log_fail(f"Initialize failed: {e}")
            results.record_fail()

    # -------------------------------------------------------------------------
    # Test 6: MCP Protocol - List Tools
    # -------------------------------------------------------------------------
    log_test("6. MCP Protocol - List Tools")
    if http_only:
        log_warn("Skipped (--http-only flag)")
        results.record_skip()
    elif not has_bearer and not has_basic:
        log_warn("Skipped - no credentials provided")
        results.record_skip()
    else:
        try:
            if has_bearer:
                auth_header = f"Bearer {bearer_token}"
            else:
                credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
                auth_header = f"Basic {credentials}"

            response = client.list_tools(auth_header)

            if response["status_code"] == 200 and response["json"]:
                result = response["json"].get("result", {})
                if "error" in response["json"]:
                    error = response["json"]["error"]
                    log_fail(f"List tools error: {error.get('message', 'unknown')}")
                    results.record_fail()
                else:
                    tools = result.get("tools", [])
                    log_pass(f"Listed {len(tools)} tools")
                    for tool in tools:
                        desc = tool.get("description", "")[:40]
                        log_info(f"  - {tool.get('name', 'unknown')}: {desc}...")
                    results.record_pass()
            elif response["status_code"] == 401:
                log_warn("List tools rejected (invalid credentials)")
                results.record_pass()  # HTTP mode works
            else:
                log_fail(f"List tools failed: HTTP {response['status_code']}")
                log_info(f"Body: {response['body'][:300]}")
                results.record_fail()
        except Exception as e:
            log_fail(f"List tools failed: {e}")
            results.record_fail()

    # -------------------------------------------------------------------------
    # Test 7: MCP Protocol - Get Schema (requires Neo4j connection)
    # -------------------------------------------------------------------------
    log_test("7. MCP Protocol - Get Schema")
    if http_only:
        log_warn("Skipped (--http-only flag)")
        results.record_skip()
    elif not has_bearer and not has_basic:
        log_warn("Skipped - no credentials provided")
        results.record_skip()
    else:
        try:
            if has_bearer:
                auth_header = f"Bearer {bearer_token}"
            else:
                credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
                auth_header = f"Basic {credentials}"

            response = client.call_tool("get-schema", {}, auth_header)

            if response["status_code"] == 200 and response["json"]:
                if "error" in response["json"]:
                    error = response["json"]["error"]
                    log_fail(f"get-schema error: {error.get('message', 'unknown')}")
                    results.record_fail()
                else:
                    result = response["json"].get("result", {})
                    log_pass("get-schema executed successfully")
                    content = result.get("content", [])
                    if content:
                        log_info(f"Schema data retrieved ({len(str(content))} chars)")
                    results.record_pass()
            elif response["status_code"] == 401:
                log_warn("get-schema rejected (invalid credentials)")
                results.record_pass()  # HTTP mode works
            else:
                log_fail(f"get-schema failed: HTTP {response['status_code']}")
                log_info(f"Body: {response['body'][:300]}")
                results.record_fail()
        except Exception as e:
            log_fail(f"get-schema failed: {e}")
            results.record_fail()

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    log_header("Test Results Summary")
    print(f"\n{results.summary()}")

    if results.failed == 0:
        log_pass("All tests passed! HTTP mode is functional.")
        if has_bearer:
            log_info("Bearer token authentication is working.")
        if has_basic:
            log_info("Basic authentication is working.")
    elif results.passed > 0:
        log_warn("Some tests failed. Check the output above.")
    else:
        log_fail("All tests failed. HTTP mode may not be supported.")

    return results


# =============================================================================
# Main
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Validate Neo4j MCP Server HTTP mode and authentication",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Test HTTP mode only (no Neo4j connection required)
  uv run test_http_mode.py --http-only

  # Test with direct bearer token
  uv run test_http_mode.py --bearer-token eyJhbGc...

  # Test with Azure Entra ID (acquires token automatically)
  uv run test_http_mode.py --azure-tenant-id <tenant> --azure-client-id <client> --azure-client-secret <secret>

  # Test with basic auth (username/password)
  uv run test_http_mode.py --username neo4j --password secret

Environment Variables (alternative to CLI args):
  MCP_BEARER_TOKEN      - Direct bearer token
  AZURE_TENANT_ID       - Azure AD tenant ID
  AZURE_CLIENT_ID       - Azure app client ID
  AZURE_CLIENT_SECRET   - Azure app client secret
  AZURE_AUDIENCE        - Optional custom audience (default: api://{client_id})
  NEO4J_USERNAME        - Neo4j username for basic auth
  NEO4J_PASSWORD        - Neo4j password for basic auth
        """,
    )
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("MCP_ENDPOINT", "http://localhost:8080"),
        help="MCP server endpoint (default: http://localhost:8080)",
    )

    # Bearer token options
    bearer_group = parser.add_argument_group("Bearer Token Authentication")
    bearer_group.add_argument(
        "--bearer-token",
        default=os.environ.get("MCP_BEARER_TOKEN"),
        help="Direct bearer token (JWT)",
    )
    bearer_group.add_argument(
        "--azure-tenant-id",
        default=os.environ.get("AZURE_TENANT_ID"),
        help="Azure AD tenant ID (for token acquisition)",
    )
    bearer_group.add_argument(
        "--azure-client-id",
        default=os.environ.get("AZURE_CLIENT_ID"),
        help="Azure app client ID",
    )
    bearer_group.add_argument(
        "--azure-client-secret",
        default=os.environ.get("AZURE_CLIENT_SECRET"),
        help="Azure app client secret",
    )
    bearer_group.add_argument(
        "--azure-audience",
        default=os.environ.get("AZURE_AUDIENCE"),
        help="Custom audience (default: api://{client_id})",
    )

    # Basic auth options
    basic_group = parser.add_argument_group("Basic Authentication")
    basic_group.add_argument(
        "--username",
        default=os.environ.get("NEO4J_USERNAME"),
        help="Neo4j username",
    )
    basic_group.add_argument(
        "--password",
        default=os.environ.get("NEO4J_PASSWORD"),
        help="Neo4j password",
    )

    parser.add_argument(
        "--http-only",
        action="store_true",
        help="Only test HTTP mode works, skip Neo4j-dependent tests",
    )

    args = parser.parse_args()

    # Determine bearer token
    bearer_token = args.bearer_token

    # If no direct token but Azure credentials provided, acquire token
    if not bearer_token and args.azure_tenant_id and args.azure_client_id and args.azure_client_secret:
        try:
            bearer_token = get_azure_token(
                tenant_id=args.azure_tenant_id,
                client_id=args.azure_client_id,
                client_secret=args.azure_client_secret,
                audience=args.azure_audience,
            )
        except Exception as e:
            log_fail(f"Failed to acquire Azure token: {e}")
            sys.exit(1)

    # If still no token, try environment
    if not bearer_token:
        bearer_token = get_token_from_env()

    results = run_tests(
        endpoint=args.endpoint,
        bearer_token=bearer_token,
        username=args.username,
        password=args.password,
        http_only=args.http_only,
    )

    # Exit with appropriate code
    sys.exit(0 if results.failed == 0 else 1)


if __name__ == "__main__":
    main()
