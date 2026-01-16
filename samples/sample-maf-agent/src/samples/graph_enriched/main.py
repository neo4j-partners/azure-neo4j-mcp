"""
Demo: Neo4j Context Provider with Graph-Enriched Mode.

Shows semantic search using neo4j-graphrag VectorCypherRetriever with
graph traversal to enrich results with company, product, and risk factor context.
"""

from __future__ import annotations

import asyncio

from samples.shared import print_header

# Graph-enriched retrieval query
# This query is appended after the vector search by VectorCypherRetriever.
# Variables available from vector search:
#   - node: The Chunk node matched by vector similarity
#   - score: Similarity score (0.0 to 1.0)
# Note: Uses explicit grouping and null-safe sorting per Cypher best practices
RETRIEVAL_QUERY = """
MATCH (node)-[:FROM_DOCUMENT]->(doc:Document)<-[:FILED]-(company:Company)
OPTIONAL MATCH (company)-[:FACES_RISK]->(risk:RiskFactor)
OPTIONAL MATCH (company)-[:MENTIONS]->(product:Product)
WITH node, score, company, doc,
     collect(DISTINCT risk.name)[0..5] AS risks,
     collect(DISTINCT product.name)[0..5] AS products
WHERE score IS NOT NULL
RETURN
    node.text AS text,
    score,
    company.name AS company,
    company.ticker AS ticker,
    risks,
    products
ORDER BY score DESC
"""


async def demo_context_provider_graph_enriched() -> None:
    """Demo: Neo4j Context Provider with graph-enriched mode."""
    from azure.identity import DefaultAzureCredential
    from azure.identity.aio import AzureCliCredential

    from agent_framework_neo4j import (
        AzureAIEmbedder,
        AzureAISettings,
        Neo4jContextProvider,
        Neo4jSettings,
    )
    from samples.shared import AgentConfig, create_agent_client, get_logger

    logger = get_logger()

    print_header("Demo: Context Provider (Graph-Enriched Mode)")
    print("This demo shows the Neo4jContextProvider with graph-enriched mode,")
    print("combining vector search with graph traversal to provide rich context")
    print("about companies, their products, and risk factors.\n")

    # Load configs
    agent_config = AgentConfig()
    neo4j_settings = Neo4jSettings()
    azure_settings = AzureAISettings()

    if not agent_config.project_endpoint:
        print("Error: AZURE_AI_PROJECT_ENDPOINT not configured.")
        return

    if not neo4j_settings.is_configured:
        print("Error: Neo4j not configured.")
        print("Required: NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD")
        return

    if not azure_settings.is_configured:
        print("Error: Azure AI not configured.")
        print("Required: AZURE_AI_PROJECT_ENDPOINT")
        return

    print(f"Agent: {agent_config.name}")
    print(f"Model: {agent_config.model}")
    print(f"Neo4j URI: {neo4j_settings.uri}")
    print(f"Vector Index: {neo4j_settings.vector_index_name}")
    print("Mode: graph_enriched")
    print(f"Embedding Model: {azure_settings.embedding_model}\n")

    print("Retrieval Query Pattern:")
    print("-" * 50)
    print("  Chunk -[:FROM_DOCUMENT]-> Document <-[:FILED]- Company")
    print("  Company -[:FACES_RISK]-> RiskFactor")
    print("  Company -[:MENTIONS]-> Product")
    print("-" * 50 + "\n")

    credential = AzureCliCredential()
    sync_credential = DefaultAzureCredential()
    embedder = None

    try:
        # Create embedder for neo4j-graphrag (uses sync credential)
        embedder = AzureAIEmbedder(
            endpoint=azure_settings.inference_endpoint,
            credential=sync_credential,
            model=azure_settings.embedding_model,
        )
        print("Embedder initialized!\n")

        # Create context provider with graph-enriched mode
        # Uses VectorCypherRetriever internally
        provider = Neo4jContextProvider(
            uri=neo4j_settings.uri,
            username=neo4j_settings.username,
            password=neo4j_settings.get_password(),
            index_name=neo4j_settings.vector_index_name,
            index_type="vector",
            retrieval_query=RETRIEVAL_QUERY,
            embedder=embedder,
            top_k=5,
            context_prompt=(
                "## Graph-Enriched Knowledge Context\n"
                "The following information combines semantic search results with "
                "graph traversal to provide company, product, and risk context:"
            ),
        )

        # Create agent client
        client = create_agent_client(agent_config, credential)

        # Use both provider and agent as async context managers
        async with provider:
            print("Connected to Neo4j with graph-enriched mode!\n")

            async with client.create_agent(
                name=agent_config.name,
                instructions=(
                    "You are a helpful assistant that answers questions about companies "
                    "using graph-enriched context. Your context includes:\n"
                    "- Semantic search matches from company filings\n"
                    "- Company names and ticker symbols\n"
                    "- Products the company mentions\n"
                    "- Risk factors the company faces\n\n"
                    "When answering, cite the company, relevant products, and risks. "
                    "Be specific and reference the enriched graph data."
                ),
                context_provider=provider,
            ) as agent:
                print("Agent created with graph-enriched context provider!\n")
                print("-" * 50)

                # Demo queries that benefit from graph enrichment
                queries = [
                    "What are Apple's main products and what risks does the company face?",
                    "Tell me about Microsoft's cloud services and business risks",
                    "What products and risks are mentioned in Amazon's filings?",
                ]

                for i, query in enumerate(queries, 1):
                    print(f"\n[Query {i}] User: {query}\n")

                    response = await agent.run(query)
                    print(f"[Query {i}] Agent: {response.text}\n")
                    print("-" * 50)

                print(
                    "\nDemo complete! Graph-enriched mode combined vector search with "
                    "graph traversal for comprehensive company context."
                )

    except ConnectionError as e:
        print(f"\nConnection Error: {e}")
        print("Please check your Neo4j and Microsoft Foundry configuration.")
    except Exception as e:
        logger.error(f"Error during demo: {e}")
        print(f"\nError: {e}")
        raise
    finally:
        # Close embedder credential
        if embedder is not None:
            embedder.close()
        await credential.close()
        # Allow pending async cleanup tasks to complete
        await asyncio.sleep(0.1)
