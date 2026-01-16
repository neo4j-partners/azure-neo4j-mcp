#!/usr/bin/env python3
"""
Simple Neo4j MCP Agent

A simplified ReAct agent that connects to the Neo4j MCP server.
Uses Azure OpenAI for LLM inference and reads configuration from .env.

Usage:
    python simple-agent.py                    # Run demo queries
    python simple-agent.py "your question"    # Ask a specific question
"""

import asyncio
import json
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain.agents import create_agent


# File paths
SCRIPT_DIR = Path(__file__).parent
SAMPLES_DIR = SCRIPT_DIR.parent
PROJECT_ROOT = SAMPLES_DIR.parent

# Load .env from samples directory (preferred) or project root
SAMPLES_ENV = SAMPLES_DIR / ".env"
PROJECT_ENV = PROJECT_ROOT / ".env"
MCP_ACCESS_FILE = PROJECT_ROOT / "MCP_ACCESS.json"


SYSTEM_PROMPT = """You are a helpful Neo4j database assistant with access to tools that let you query a Neo4j graph database.

Your capabilities include:
- Retrieve the database schema to understand node labels, relationship types, and properties
- Execute read-only Cypher queries to answer questions about the data
- Do not execute any write Cypher queries

When answering questions about the database:
1. First retrieve the schema to understand the database structure
2. Formulate appropriate Cypher queries based on the actual schema
3. If a query returns no results, explain what you looked for and suggest alternatives
4. Format results in a clear, human-readable way
5. Cite the actual data returned in your response

Important Cypher notes:
- Use MATCH patterns that align with the actual schema
- For counting, use MATCH (n:Label) RETURN count(n)
- For listing items, add LIMIT to avoid overwhelming results
- Handle potential NULL values gracefully

Be concise but thorough in your responses."""

DEMO_QUESTIONS = [
    ("Database Schema Overview", "What is the database schema? Give me a brief summary."),
    ("Count of Companies", "How many Company nodes are in the database?"),
    ("Financial Metrics", "What financial metrics are mentioned in the SEC filings? Show a few examples."),
]


def load_config() -> tuple[str, str, str, str]:
    """
    Load configuration from .env files and MCP_ACCESS.json.

    Returns:
        tuple: (mcp_url, api_key, azure_endpoint, model_name)
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
    model_name = os.getenv("AZURE_AI_MODEL_NAME", "gpt-4o")

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

    return mcp_endpoint, api_key, azure_endpoint, model_name


def get_llm(azure_endpoint: str, model_name: str):
    """Get the LLM to use for the agent (Azure OpenAI)."""
    from azure.identity import AzureCliCredential, get_bearer_token_provider
    from langchain_openai import AzureChatOpenAI

    # Use Azure CLI credential with token provider
    credential = AzureCliCredential()
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default"
    )

    return AzureChatOpenAI(
        azure_endpoint=azure_endpoint,
        azure_deployment=model_name,
        api_version="2024-10-21",
        azure_ad_token_provider=token_provider,
        temperature=0,
    )


async def run_agent(question: str):
    """Run the LangGraph agent with the given question."""
    print("=" * 70)
    print("Neo4j MCP Agent")
    print("=" * 70)
    print()

    # Load configuration
    mcp_url, api_key, azure_endpoint, model_name = load_config()

    print(f"MCP Server: {mcp_url}")
    print(f"Azure AI: {azure_endpoint}")
    print(f"Model: {model_name}")
    print()

    # Initialize LLM
    print("Initializing Azure OpenAI LLM...")
    llm = get_llm(azure_endpoint, model_name)
    print()

    # Connect to MCP server
    print("Connecting to MCP server...")

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

    # Get available tools (new API - no context manager)
    tools = await client.get_tools()
    print(f"Loaded {len(tools)} tools: {[t.name for t in tools]}")
    print()

    # Create the ReAct agent
    print("Creating agent...")
    agent = create_agent(
        llm,
        tools,
        system_prompt=SYSTEM_PROMPT,
    )

    # Run the agent
    print("=" * 70)
    print(f"Question: {question}")
    print("=" * 70)
    print()

    result = await agent.ainvoke({"messages": [("user", question)]})

    # Extract and print the final response
    messages = result.get("messages", [])
    if messages:
        final_message = messages[-1]
        if hasattr(final_message, "content"):
            print("Answer:")
            print("-" * 70)
            print(final_message.content)
            print("-" * 70)
        else:
            print("Answer:", final_message)
    else:
        print("No response from agent")


async def run_demo():
    """Run demo queries to showcase the agent capabilities."""
    print()
    print("#" * 76)
    print("#" + "NEO4J MCP AGENT DEMO".center(74) + "#")
    print("#" * 76)
    print()

    for i, (title, question) in enumerate(DEMO_QUESTIONS, 1):
        print()
        print("=" * 76)
        print(f"  QUERY {i}: {title}")
        print("=" * 76)
        print()
        await run_agent(question)
        print()

    print()
    print("#" * 76)
    print("#" + "DEMO COMPLETE".center(74) + "#")
    print("#" * 76)


def main():
    if len(sys.argv) < 2:
        asyncio.run(run_demo())
    else:
        question = " ".join(sys.argv[1:])
        asyncio.run(run_agent(question))


if __name__ == "__main__":
    main()
