#!/usr/bin/env python3
"""
Test: Vector Embedding Search via MCP Server

Verifies that the MCP server's read-cypher tool can execute a vector
similarity search against the Neo4j chunkEmbeddings index.

Steps:
1. Generate an embedding for a test query using Azure OpenAI (text-embedding-3-small)
2. Connect to the Neo4j MCP server
3. Execute a vector search via the read-cypher MCP tool
4. Verify results are returned

Usage:
    python test-vector-search.py                       # Run with default query
    python test-vector-search.py "your search query"   # Run with custom query
"""

import asyncio
import json
import os
import sys
from pathlib import Path

from azure.identity import AzureCliCredential, get_bearer_token_provider
from dotenv import load_dotenv
from langchain_mcp_adapters.client import MultiServerMCPClient
from openai import AzureOpenAI


# File paths
SCRIPT_DIR = Path(__file__).parent
SAMPLES_DIR = SCRIPT_DIR.parent
PROJECT_ROOT = SAMPLES_DIR.parent

# Load .env from samples directory (preferred) or project root
SAMPLES_ENV = SAMPLES_DIR / ".env"
PROJECT_ENV = PROJECT_ROOT / ".env"
MCP_ACCESS_FILE = PROJECT_ROOT / "MCP_ACCESS.json"

DEFAULT_QUERY = "What are the risk factors for the company?"
VECTOR_INDEX_NAME = "chunkEmbeddings"
TOP_K = 5


def load_config() -> tuple[str, str, str, str]:
    """
    Load configuration from .env files and MCP_ACCESS.json.

    Returns:
        tuple: (mcp_url, api_key, azure_endpoint, embedding_model)
    """
    # Load .env file - prefer samples/.env, fallback to project root
    if SAMPLES_ENV.exists():
        load_dotenv(SAMPLES_ENV)
        print(f"Loaded config from: {SAMPLES_ENV}")
    elif PROJECT_ENV.exists():
        load_dotenv(PROJECT_ENV)
        print(f"Loaded config from: {PROJECT_ENV}")
    else:
        print("WARNING: No .env file found")

    # Get Azure AI configuration
    azure_endpoint = os.getenv("AZURE_AI_SERVICES_ENDPOINT")
    embedding_model = os.getenv("AZURE_AI_EMBEDDING_NAME", "text-embedding-3-small")

    if not azure_endpoint:
        print("ERROR: AZURE_AI_SERVICES_ENDPOINT not found in environment")
        print()
        print("Run from samples directory:")
        print("  ./scripts/setup_azure.sh")
        print("  azd up")
        print("  uv run python setup_env.py")
        sys.exit(1)

    # Get MCP configuration - prefer env vars, fallback to MCP_ACCESS.json
    mcp_endpoint = os.getenv("MCP_ENDPOINT")
    api_key = os.getenv("MCP_API_KEY")

    if not mcp_endpoint or not api_key:
        # Try loading from MCP_ACCESS.json
        if MCP_ACCESS_FILE.exists():
            with open(MCP_ACCESS_FILE) as f:
                mcp_access = json.load(f)
            endpoint = mcp_access.get("endpoint", "")
            mcp_path = mcp_access.get("mcp_path", "/mcp")
            mcp_endpoint = f"{endpoint.rstrip('/')}{mcp_path}"
            api_key = mcp_access.get("api_key", api_key)
        else:
            print("ERROR: MCP configuration not found")
            print()
            print("Either set MCP_ENDPOINT and MCP_API_KEY in .env")
            print("Or run './scripts/deploy.sh' from project root to generate MCP_ACCESS.json")
            sys.exit(1)

    return mcp_endpoint, api_key, azure_endpoint, embedding_model


def generate_embedding(azure_endpoint: str, model_name: str, text: str) -> list[float]:
    """Generate an embedding using Azure OpenAI."""
    credential = AzureCliCredential()
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default"
    )

    client = AzureOpenAI(
        azure_endpoint=azure_endpoint,
        azure_ad_token_provider=token_provider,
        api_version="2024-10-21",
    )

    response = client.embeddings.create(
        input=text,
        model=model_name,
    )

    return response.data[0].embedding


async def test_vector_search(query: str):
    """Test vector search through the MCP server's read-cypher tool."""
    print("=" * 70)
    print("Vector Embedding Search Test")
    print("=" * 70)
    print()

    # Load configuration
    mcp_url, api_key, azure_endpoint, embedding_model = load_config()
    print(f"MCP Server: {mcp_url}")
    print(f"Embedding Model: {embedding_model}")
    print()

    # Step 1: Generate embedding
    print(f'Step 1: Generating embedding for: "{query}"')
    embedding = generate_embedding(azure_endpoint, embedding_model, query)
    print(f"  Embedding dimensions: {len(embedding)}")
    print(f"  First 5 values: {embedding[:5]}")
    print()

    if len(embedding) != 1536:
        print(f"  FAIL: Expected 1536 dimensions, got {len(embedding)}")
        sys.exit(1)

    # Step 2: Connect to MCP server
    print("Step 2: Connecting to MCP server...")
    client = MultiServerMCPClient(
        {
            "neo4j": {
                "transport": "streamable_http",
                "url": mcp_url,
                "headers": {
                    "Authorization": f"Bearer {api_key}",
                },
            }
        }
    )

    tools = await client.get_tools()
    tool_names = [t.name for t in tools]
    print(f"  Available tools: {tool_names}")

    # Find the read-cypher tool
    read_cypher = next((t for t in tools if t.name == "read-cypher"), None)
    if not read_cypher:
        print("  FAIL: read-cypher tool not found")
        sys.exit(1)
    print("  Found read-cypher tool")
    print()

    # Step 3: Execute vector search via MCP read-cypher
    print("Step 3: Executing vector search via MCP read-cypher...")

    # Format embedding as Cypher list literal
    embedding_str = ", ".join(str(v) for v in embedding)
    cypher_query = (
        f"WITH [{embedding_str}] AS embedding "
        f"CALL db.index.vector.queryNodes('{VECTOR_INDEX_NAME}', {TOP_K}, embedding) "
        "YIELD node, score "
        "RETURN node.text AS text, score "
        "ORDER BY score DESC"
    )

    print(f"  Index: {VECTOR_INDEX_NAME}")
    print(f"  Top K: {TOP_K}")

    result = await read_cypher.ainvoke({"query": cypher_query})
    print()

    # Step 4: Verify results
    print("Step 4: Verifying results...")
    print("-" * 70)

    if not result:
        print("  FAIL: No results returned")
        sys.exit(1)

    # Display results
    if isinstance(result, str):
        print(result)
        has_results = len(result.strip()) > 0 and "score" in result.lower()
    else:
        print(
            json.dumps(result, indent=2)
            if isinstance(result, (dict, list))
            else str(result)
        )
        has_results = True

    print("-" * 70)
    print()

    if has_results:
        print("PASS: Vector search returned results via MCP read-cypher")
    else:
        print("FAIL: Vector search did not return expected results")
        sys.exit(1)


def main():
    if len(sys.argv) > 1:
        query = " ".join(sys.argv[1:])
    else:
        query = DEFAULT_QUERY

    asyncio.run(test_vector_search(query))


if __name__ == "__main__":
    main()
