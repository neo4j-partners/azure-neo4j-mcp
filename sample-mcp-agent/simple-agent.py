#!/usr/bin/env python3
"""
Simple Neo4j MCP Agent

A simplified ReAct agent that connects to the Neo4j MCP server.
Uses MCP_ACCESS.json for connection info and .env for the API key.

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


# File paths (relative to this script's directory)
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
MCP_ACCESS_FILE = PROJECT_ROOT / "MCP_ACCESS.json"
ENV_FILE = PROJECT_ROOT / ".env"

MODEL_ID = "us.anthropic.claude-sonnet-4-20250514-v1:0"

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
    ("Count of Aircraft", "How many Aircraft are in the database?"),
    ("List Airports", "List 5 airports with their city and country."),
]


def load_config() -> tuple[str, str, str]:
    """
    Load configuration from MCP_ACCESS.json and .env file.

    Returns:
        tuple: (mcp_url, api_key, region)
    """
    # Load .env file from project root
    if ENV_FILE.exists():
        load_dotenv(ENV_FILE)
    else:
        print(f"WARNING: .env file not found at {ENV_FILE}")

    # Get API key from environment
    api_key = os.getenv("MCP_API_KEY")
    if not api_key:
        print("ERROR: MCP_API_KEY not found in environment or .env file")
        print()
        print("Add MCP_API_KEY to your .env file:")
        print("  MCP_API_KEY=your-api-key-here")
        sys.exit(1)

    # Load MCP_ACCESS.json for connection info
    if not MCP_ACCESS_FILE.exists():
        print(f"ERROR: MCP_ACCESS.json not found at {MCP_ACCESS_FILE}")
        print()
        print("Run './scripts/deploy.sh' to deploy the MCP server and generate this file")
        sys.exit(1)

    with open(MCP_ACCESS_FILE) as f:
        mcp_access = json.load(f)

    # Construct the full MCP URL from endpoint + mcp_path
    endpoint = mcp_access.get("endpoint", "")
    mcp_path = mcp_access.get("mcp_path", "/mcp")
    mcp_url = f"{endpoint.rstrip('/')}{mcp_path}"

    # Get region (default to us-west-2 for Bedrock)
    region = os.getenv("AWS_REGION", "us-west-2")

    return mcp_url, api_key, region


def get_llm(region: str = "us-west-2"):
    """Get the LLM to use for the agent (AWS Bedrock Claude via Converse API)."""
    from langchain_aws import ChatBedrockConverse

    return ChatBedrockConverse(
        model=MODEL_ID,
        region_name=region,
        temperature=0,
    )


async def run_agent(question: str):
    """Run the LangGraph agent with the given question."""
    print("=" * 70)
    print("Neo4j MCP Agent")
    print("=" * 70)
    print()

    # Load configuration
    mcp_url, api_key, region = load_config()

    print(f"MCP Server: {mcp_url}")
    print()

    # Initialize LLM
    print(f"Initializing LLM (Bedrock, region: {region})...")
    llm = get_llm(region)
    print(f"Using: {llm.model_id}")
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
    print(f"Loaded {len(tools)} tools:")
    for tool in tools:
        print(f"  - {tool.name}")
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
