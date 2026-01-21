#!/usr/bin/env python3
"""
Bearer Token MCP Client - Test Script

This script demonstrates how to authenticate with an identity provider and
call the Neo4j MCP server using bearer token authentication.

Usage:
    # Set environment variables
    export MCP_ENDPOINT="https://your-mcp-server.azurecontainerapps.io"

    # For Azure Entra ID:
    export AZURE_TENANT_ID="your-tenant-id"
    export AZURE_CLIENT_ID="your-client-id"
    export AZURE_CLIENT_SECRET="your-client-secret"

    # Run tests
    python test_bearer_client.py

Requirements:
    pip install msal requests
"""

import json
import os
import sys
from typing import Optional

import requests

# Optional: MSAL for Azure Entra ID token acquisition
try:
    from msal import ConfidentialClientApplication
    MSAL_AVAILABLE = True
except ImportError:
    MSAL_AVAILABLE = False
    print("Note: msal not installed. Azure Entra ID auth not available.")
    print("Install with: pip install msal")


class MCPBearerClient:
    """MCP client with bearer token authentication."""

    def __init__(self, endpoint: str, token: str):
        """
        Initialize the MCP client.

        Args:
            endpoint: MCP server endpoint (e.g., https://xxx.azurecontainerapps.io)
            token: Bearer token for authentication
        """
        self.endpoint = endpoint.rstrip("/")
        self.mcp_url = f"{self.endpoint}/mcp"
        self.token = token
        self.request_id = 0

    def _call(self, method: str, params: Optional[dict] = None) -> dict:
        """Make a JSON-RPC call to the MCP server."""
        self.request_id += 1

        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "id": self.request_id
        }
        if params:
            payload["params"] = params

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.token}"
        }

        response = requests.post(
            self.mcp_url,
            json=payload,
            headers=headers,
            timeout=30
        )

        if response.status_code == 401:
            raise Exception("Authentication failed: Invalid or expired token")
        if response.status_code == 403:
            raise Exception("Authorization failed: Insufficient permissions")

        response.raise_for_status()
        return response.json()

    def initialize(self) -> dict:
        """Initialize the MCP connection."""
        return self._call("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {
                "name": "bearer-test-client",
                "version": "1.0.0"
            }
        })

    def list_tools(self) -> dict:
        """List available MCP tools."""
        return self._call("tools/list")

    def call_tool(self, name: str, arguments: dict) -> dict:
        """Call an MCP tool."""
        return self._call("tools/call", {
            "name": name,
            "arguments": arguments
        })

    def get_schema(self) -> dict:
        """Get the Neo4j database schema."""
        return self.call_tool("get-schema", {})

    def read_cypher(self, query: str) -> dict:
        """Execute a read-only Cypher query."""
        return self.call_tool("read-cypher", {"query": query})


def get_azure_token(tenant_id: str, client_id: str, client_secret: str) -> str:
    """
    Obtain a token from Azure Entra ID.

    Args:
        tenant_id: Azure AD tenant ID
        client_id: Application (client) ID
        client_secret: Client secret

    Returns:
        Access token string
    """
    if not MSAL_AVAILABLE:
        raise ImportError("msal is required for Azure Entra ID authentication")

    app = ConfidentialClientApplication(
        client_id=client_id,
        authority=f"https://login.microsoftonline.com/{tenant_id}",
        client_credential=client_secret
    )

    # Acquire token for the application itself
    result = app.acquire_token_for_client(
        scopes=[f"api://{client_id}/.default"]
    )

    if "access_token" not in result:
        error = result.get("error_description", result.get("error", "Unknown error"))
        raise Exception(f"Failed to acquire token: {error}")

    return result["access_token"]


def get_token_from_env() -> str:
    """Get token from environment, either directly or via Azure."""
    # Check for direct token
    token = os.environ.get("MCP_BEARER_TOKEN")
    if token:
        return token

    # Check for Azure credentials
    tenant_id = os.environ.get("AZURE_TENANT_ID")
    client_id = os.environ.get("AZURE_CLIENT_ID")
    client_secret = os.environ.get("AZURE_CLIENT_SECRET")

    if tenant_id and client_id and client_secret:
        print("Acquiring token from Azure Entra ID...")
        return get_azure_token(tenant_id, client_id, client_secret)

    raise ValueError(
        "No authentication configured. Set either:\n"
        "  - MCP_BEARER_TOKEN: Direct bearer token\n"
        "  - AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET: Azure Entra ID credentials"
    )


def load_endpoint_from_config() -> str:
    """Load endpoint from MCP_ACCESS.json if available."""
    config_paths = [
        "MCP_ACCESS.json",
        "../MCP_ACCESS.json",
        os.path.expanduser("~/MCP_ACCESS.json")
    ]

    for path in config_paths:
        if os.path.exists(path):
            with open(path) as f:
                config = json.load(f)
                return config.get("endpoint", "")

    return ""


def run_tests(client: MCPBearerClient):
    """Run test suite against the MCP server."""
    print("\n" + "=" * 60)
    print("Bearer Token MCP Client Tests")
    print("=" * 60)

    # Test 1: Initialize
    print("\n[Test 1] Initialize connection...")
    try:
        result = client.initialize()
        print(f"  ✓ Protocol version: {result.get('result', {}).get('protocolVersion', 'unknown')}")
        print(f"  ✓ Server: {result.get('result', {}).get('serverInfo', {}).get('name', 'unknown')}")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False

    # Test 2: List tools
    print("\n[Test 2] List available tools...")
    try:
        result = client.list_tools()
        tools = result.get("result", {}).get("tools", [])
        print(f"  ✓ Found {len(tools)} tools:")
        for tool in tools:
            print(f"    - {tool.get('name')}: {tool.get('description', '')[:50]}...")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False

    # Test 3: Get schema
    print("\n[Test 3] Get database schema...")
    try:
        result = client.get_schema()
        content = result.get("result", {}).get("content", [])
        if content:
            schema_text = content[0].get("text", "")
            lines = schema_text.split("\n")[:5]
            print(f"  ✓ Schema retrieved ({len(schema_text)} chars)")
            for line in lines:
                if line.strip():
                    print(f"    {line[:60]}...")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        # Don't fail test suite - schema might be empty

    # Test 4: Execute Cypher query
    print("\n[Test 4] Execute Cypher query...")
    try:
        result = client.read_cypher("RETURN 1 AS test, 'bearer-auth-works' AS message")
        content = result.get("result", {}).get("content", [])
        if content:
            print(f"  ✓ Query executed successfully")
            print(f"    Result: {content[0].get('text', '')[:100]}")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        return False

    # Test 5: Count nodes
    print("\n[Test 5] Count nodes in database...")
    try:
        result = client.read_cypher("MATCH (n) RETURN count(n) AS nodeCount")
        content = result.get("result", {}).get("content", [])
        if content:
            print(f"  ✓ Node count query executed")
            print(f"    Result: {content[0].get('text', '')}")
    except Exception as e:
        print(f"  ✗ Failed: {e}")
        # Don't fail - might be permission issue

    print("\n" + "=" * 60)
    print("All critical tests passed!")
    print("=" * 60)
    return True


def main():
    """Main entry point."""
    # Get endpoint
    endpoint = os.environ.get("MCP_ENDPOINT") or load_endpoint_from_config()
    if not endpoint:
        print("Error: MCP_ENDPOINT not set and MCP_ACCESS.json not found")
        print("Set MCP_ENDPOINT environment variable or ensure MCP_ACCESS.json exists")
        sys.exit(1)

    print(f"MCP Endpoint: {endpoint}")

    # Get token
    try:
        token = get_token_from_env()
        print("Token acquired successfully")
        # Show token info (first/last few chars for debugging)
        print(f"Token preview: {token[:20]}...{token[-10:]}")
    except Exception as e:
        print(f"Error acquiring token: {e}")
        sys.exit(1)

    # Create client and run tests
    client = MCPBearerClient(endpoint, token)

    success = run_tests(client)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
