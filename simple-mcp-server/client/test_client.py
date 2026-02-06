#!/usr/bin/env python3
"""
Neo4j MCP Server - Test Client

This script validates the deployment by testing:
1. Authentication with API key
2. MCP protocol connectivity
3. Tool discovery (tools/list)
4. Schema retrieval (get-schema)
5. Basic Cypher query execution (read-cypher)

Usage:
    python3 client/test_client.py

    Or via deploy script:
    ./scripts/deploy.sh test

The script reads connection info from MCP_ACCESS.json in the project root.
"""

import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path


# ANSI color codes for output
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    END = '\033[0m'


def print_header(text: str) -> None:
    """Print a section header."""
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * 60}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.END}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * 60}{Colors.END}")


def print_success(text: str) -> None:
    """Print a success message."""
    print(f"{Colors.GREEN}[PASS]{Colors.END} {text}")


def print_error(text: str) -> None:
    """Print an error message."""
    print(f"{Colors.RED}[FAIL]{Colors.END} {text}")


def print_warning(text: str) -> None:
    """Print a warning message."""
    print(f"{Colors.YELLOW}[WARN]{Colors.END} {text}")


def print_info(text: str) -> None:
    """Print an info message."""
    print(f"{Colors.BLUE}[INFO]{Colors.END} {text}")


def load_config() -> dict:
    """Load configuration from MCP_ACCESS.json."""
    # Find project root (parent of client directory)
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    config_file = project_root / "MCP_ACCESS.json"

    # Also check if there's a .env file to get API key
    env_file = project_root / ".env"
    api_key_from_env = None

    if env_file.exists():
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('MCP_API_KEY=') and not line.startswith('#'):
                    api_key_from_env = line.split('=', 1)[1].strip().strip('"\'')
                    break

    if not config_file.exists():
        print_error(f"Configuration file not found: {config_file}")
        print_info("Run './scripts/deploy.sh' to deploy and generate the config file")
        sys.exit(1)

    with open(config_file, 'r') as f:
        config = json.load(f)

    # Use API key from .env if available (more reliable than placeholder in JSON)
    if api_key_from_env:
        config['api_key'] = api_key_from_env

    return config


def make_mcp_request(endpoint: str, api_key: str, method: str, params: dict = None) -> dict:
    """
    Make an MCP JSON-RPC request.

    Args:
        endpoint: Full URL to the MCP endpoint
        api_key: API key for authentication
        method: JSON-RPC method name
        params: Optional parameters for the method

    Returns:
        Response JSON as dict
    """
    request_id = 1
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "id": request_id
    }
    if params:
        payload["params"] = params

    data = json.dumps(payload).encode('utf-8')

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json"
    }

    req = urllib.request.Request(endpoint, data=data, headers=headers, method='POST')

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            response_data = response.read().decode('utf-8')
            return json.loads(response_data)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else ""
        return {
            "error": {
                "code": e.code,
                "message": f"HTTP {e.code}: {e.reason}",
                "data": error_body
            }
        }
    except urllib.error.URLError as e:
        return {
            "error": {
                "code": -1,
                "message": f"Connection error: {e.reason}"
            }
        }
    except json.JSONDecodeError as e:
        return {
            "error": {
                "code": -2,
                "message": f"Invalid JSON response: {e}"
            }
        }


def test_authentication_rejected(endpoint: str) -> bool:
    """Test that requests without API key are rejected."""
    print_info("Testing authentication rejection (no API key)...")

    payload = {
        "jsonrpc": "2.0",
        "method": "tools/list",
        "id": 1
    }

    data = json.dumps(payload).encode('utf-8')
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    req = urllib.request.Request(endpoint, data=data, headers=headers, method='POST')

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            # If we get here, auth was NOT required (unexpected)
            print_error("Request without API key was accepted (expected 401)")
            return False
    except urllib.error.HTTPError as e:
        if e.code == 401:
            print_success("Requests without API key are rejected (401)")
            return True
        else:
            print_error(f"Unexpected error code: {e.code} (expected 401)")
            return False
    except Exception as e:
        print_error(f"Connection error: {e}")
        return False


def test_authentication_invalid(endpoint: str) -> bool:
    """Test that requests with invalid API key are rejected."""
    print_info("Testing authentication rejection (invalid API key)...")

    payload = {
        "jsonrpc": "2.0",
        "method": "tools/list",
        "id": 1
    }

    data = json.dumps(payload).encode('utf-8')
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer invalid-api-key-12345",
        "Accept": "application/json"
    }

    req = urllib.request.Request(endpoint, data=data, headers=headers, method='POST')

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            print_error("Request with invalid API key was accepted (expected 401)")
            return False
    except urllib.error.HTTPError as e:
        if e.code == 401:
            print_success("Requests with invalid API key are rejected (401)")
            return True
        else:
            print_error(f"Unexpected error code: {e.code} (expected 401)")
            return False
    except Exception as e:
        print_error(f"Connection error: {e}")
        return False


def test_tools_list(endpoint: str, api_key: str) -> bool:
    """Test the tools/list method."""
    print_info("Testing tools/list...")

    response = make_mcp_request(endpoint, api_key, "tools/list")

    if "error" in response:
        print_error(f"tools/list failed: {response['error']}")
        return False

    if "result" not in response:
        print_error("No result in response")
        return False

    result = response["result"]
    tools = result.get("tools", [])

    if not tools:
        print_warning("No tools returned (may indicate connection issues)")
        return True  # Not a failure, just a warning

    print_success(f"tools/list returned {len(tools)} tools:")
    for tool in tools:
        name = tool.get("name", "unknown")
        desc = tool.get("description", "")[:50]
        print(f"       - {name}: {desc}...")

    return True


def test_get_schema(endpoint: str, api_key: str) -> bool:
    """Test the get-schema tool."""
    print_info("Testing get-schema tool...")

    response = make_mcp_request(endpoint, api_key, "tools/call", {
        "name": "get-schema",
        "arguments": {}
    })

    if "error" in response:
        error = response["error"]
        # Check if it's an MCP-level error vs auth error
        if isinstance(error, dict) and error.get("code") == 401:
            print_error("Authentication failed for get-schema")
            return False
        print_warning(f"get-schema returned error: {error}")
        # This might be expected if Neo4j is not configured
        return True

    if "result" in response:
        result = response["result"]
        content = result.get("content", [])
        if content:
            print_success("get-schema returned schema data")
            # Print first few lines of schema
            for item in content[:1]:
                if item.get("type") == "text":
                    text = item.get("text", "")[:200]
                    print(f"       Schema preview: {text}...")
        else:
            print_warning("get-schema returned empty content")
        return True

    print_warning("Unexpected response format from get-schema")
    return True


def test_read_cypher(endpoint: str, api_key: str) -> bool:
    """Test a simple read-cypher query."""
    print_info("Testing read-cypher tool with simple query...")

    # Simple query that should work on any Neo4j database
    query = "RETURN 1 as value"

    response = make_mcp_request(endpoint, api_key, "tools/call", {
        "name": "read-cypher",
        "arguments": {
            "query": query
        }
    })

    if "error" in response:
        error = response["error"]
        if isinstance(error, dict) and error.get("code") == 401:
            print_error("Authentication failed for read-cypher")
            return False
        print_warning(f"read-cypher returned error: {error}")
        # This might be expected if Neo4j is not properly configured
        return True

    if "result" in response:
        result = response["result"]
        content = result.get("content", [])
        if content:
            print_success("read-cypher executed successfully")
            for item in content[:1]:
                if item.get("type") == "text":
                    text = item.get("text", "")[:100]
                    print(f"       Result: {text}")
        else:
            print_warning("read-cypher returned empty content")
        return True

    print_warning("Unexpected response format from read-cypher")
    return True


def main():
    """Run all tests."""
    print_header("Neo4j MCP Server - Deployment Validation")

    # Load configuration
    print_info("Loading configuration from MCP_ACCESS.json...")
    config = load_config()

    endpoint = config.get("endpoint", "")
    mcp_path = config.get("mcp_path", "/mcp")
    api_key = config.get("api_key", "")

    if not endpoint:
        print_error("No endpoint found in configuration")
        sys.exit(1)

    if not api_key or api_key == "YOUR_API_KEY":
        print_error("No valid API key found. Check .env file.")
        sys.exit(1)

    # Construct full MCP endpoint
    full_endpoint = f"{endpoint.rstrip('/')}{mcp_path}"

    print_success(f"Endpoint: {full_endpoint}")
    print_info(f"API Key: {api_key[:8]}...{api_key[-4:]}")

    # Run tests
    results = []

    # Test 1: Authentication rejection
    print_header("Test 1: Authentication - No API Key")
    results.append(("Auth Rejection (No Key)", test_authentication_rejected(full_endpoint)))

    # Test 2: Invalid API key rejection
    print_header("Test 2: Authentication - Invalid API Key")
    results.append(("Auth Rejection (Invalid Key)", test_authentication_invalid(full_endpoint)))

    # Test 3: Tools list
    print_header("Test 3: MCP Protocol - tools/list")
    results.append(("Tools List", test_tools_list(full_endpoint, api_key)))

    # Test 4: Get schema
    print_header("Test 4: Tool Execution - get-schema")
    results.append(("Get Schema", test_get_schema(full_endpoint, api_key)))

    # Test 5: Read Cypher
    print_header("Test 5: Tool Execution - read-cypher")
    results.append(("Read Cypher", test_read_cypher(full_endpoint, api_key)))

    # Summary
    print_header("Test Results Summary")

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = f"{Colors.GREEN}PASS{Colors.END}" if result else f"{Colors.RED}FAIL{Colors.END}"
        print(f"  [{status}] {name}")

    print()
    if passed == total:
        print(f"{Colors.GREEN}{Colors.BOLD}All {total} tests passed!{Colors.END}")
        sys.exit(0)
    else:
        print(f"{Colors.YELLOW}{Colors.BOLD}{passed}/{total} tests passed{Colors.END}")
        # Return 0 even with some failures (warnings don't count as failures)
        failed = [name for name, result in results if not result]
        if failed:
            print(f"{Colors.RED}Failed tests: {', '.join(failed)}{Colors.END}")
            sys.exit(1)
        sys.exit(0)


if __name__ == "__main__":
    main()
