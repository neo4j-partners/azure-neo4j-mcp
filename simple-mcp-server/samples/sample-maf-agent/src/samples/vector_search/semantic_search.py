"""
Demo: Semantic search over Neo4j graph database.

This sample demonstrates semantic search with graph-aware context retrieval
using the Neo4jContextProvider with vector search mode.
"""

from __future__ import annotations

import asyncio

from samples.shared import print_header

# Retrieval query for graph-enriched search results
# Note: Uses explicit grouping and null-safe sorting per Cypher best practices
RETRIEVAL_QUERY = """
MATCH (node)-[:FROM_DOCUMENT]->(doc:Document)<-[:FILED]-(company:Company)
OPTIONAL MATCH (company)-[:FACES_RISK]->(risk:RiskFactor)
WITH node, score, company, collect(DISTINCT risk.name) AS risks
WHERE score IS NOT NULL
RETURN
    node.text AS text,
    score,
    company.name AS company,
    risks
ORDER BY score DESC
"""


async def demo_semantic_search() -> None:
    """Demo: Semantic search over Neo4j graph database."""
    from azure.identity import DefaultAzureCredential

    from agent_framework_neo4j import (
        AzureAIEmbedder,
        AzureAISettings,
        Neo4jContextProvider,
        Neo4jSettings,
    )
    from samples.shared import get_logger

    logger = get_logger()

    print_header("Demo: Semantic Search")
    print("This demo shows semantic search with graph-aware context retrieval.\n")

    neo4j_settings = Neo4jSettings()
    azure_settings = AzureAISettings()

    if not neo4j_settings.is_configured:
        print("Error: Neo4j not configured.")
        print("Required environment variables:")
        print("  - NEO4J_URI")
        print("  - NEO4J_USERNAME")
        print("  - NEO4J_PASSWORD")
        return

    if not azure_settings.is_configured:
        print("Error: Azure AI not configured.")
        print("Required environment variables:")
        print("  - AZURE_AI_PROJECT_ENDPOINT")
        return

    print(f"Neo4j URI: {neo4j_settings.uri}")
    print(f"Vector Index: {neo4j_settings.vector_index_name}")
    print(f"Embedding Model: {azure_settings.embedding_model}\n")

    sync_credential = DefaultAzureCredential()
    embedder = None

    try:
        # Create embedder for neo4j-graphrag
        embedder = AzureAIEmbedder(
            endpoint=azure_settings.inference_endpoint,
            credential=sync_credential,
            model=azure_settings.embedding_model,
        )
        print("Embedder initialized!\n")

        # Create context provider with vector search and graph enrichment
        provider = Neo4jContextProvider(
            uri=neo4j_settings.uri,
            username=neo4j_settings.username,
            password=neo4j_settings.get_password(),
            index_name=neo4j_settings.vector_index_name,
            index_type="vector",
            retrieval_query=RETRIEVAL_QUERY,
            embedder=embedder,
            top_k=3,
        )

        async with provider:
            print("Connected to Neo4j!\n")
            print("-" * 50)

            # Demo queries
            queries = [
                "What products does Microsoft offer?",
                "What are the risk factors for technology companies?",
                "Tell me about financial metrics and revenue",
            ]

            for i, query in enumerate(queries, 1):
                print(f"\n[Query {i}] {query}\n")

                # Perform search using the provider's internal retriever
                result = await provider._search(query)

                if not result.items:
                    print("  No results found.\n")
                    continue

                for j, item in enumerate(result.items, 1):
                    score = item.metadata.get("score", 0.0) if item.metadata else 0.0
                    company = item.metadata.get("company", "N/A") if item.metadata else "N/A"
                    risks = item.metadata.get("risks", []) if item.metadata else []

                    print(f"  Result {j} (score: {score:.3f}):")
                    print(f"    Company: {company}")
                    text_preview = str(item.content)[:150].replace("\n", " ")
                    print(f"    Text: {text_preview}...")
                    if risks:
                        print(f"    Related Risks: {', '.join(risks[:3])}")
                    print()

                print("-" * 50)

            print(
                "\nDemo complete! Semantic search successfully retrieved graph-enriched results."
            )

    except ConnectionError as e:
        print(f"\nConnection Error: {e}")
        print("Please check your Neo4j configuration and ensure the database is running.")
    except Exception as e:
        logger.error(f"Error during demo: {e}")
        print(f"\nError: {e}")
        raise
    finally:
        if embedder is not None:
            embedder.close()
        # Allow pending async cleanup tasks to complete
        await asyncio.sleep(0.1)
