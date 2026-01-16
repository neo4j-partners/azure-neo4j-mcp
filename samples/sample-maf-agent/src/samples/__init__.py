"""
Neo4j MAF Provider Sample Applications.

This package contains demo applications showcasing:
- agent-framework-neo4j context providers (Financial Documents)
- MCP server integration for Neo4j via MCPStreamableHTTPTool
"""

from .basic_fulltext import demo_context_provider_basic
from .graph_enriched import demo_context_provider_graph_enriched
from .mcp_tools import demo_mcp_tools
from .vector_search import demo_context_provider_vector, demo_semantic_search

__all__ = [
    "demo_semantic_search",
    "demo_context_provider_basic",
    "demo_context_provider_vector",
    "demo_context_provider_graph_enriched",
    "demo_mcp_tools",
]
