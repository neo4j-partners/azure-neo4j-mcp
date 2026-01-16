"""
Neo4j MAF Provider Sample Applications - Financial Documents.

This package contains demo applications showcasing the agent-framework-neo4j library.
"""

from .basic_fulltext import demo_context_provider_basic
from .graph_enriched import demo_context_provider_graph_enriched
from .vector_search import demo_context_provider_vector, demo_semantic_search

__all__ = [
    "demo_semantic_search",
    "demo_context_provider_basic",
    "demo_context_provider_vector",
    "demo_context_provider_graph_enriched",
]
