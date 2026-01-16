"""
Demo: Neo4j Context Provider with Vector Search.

Shows semantic search using neo4j-graphrag VectorRetriever with
Azure AI embeddings and ChatAgent.
"""

from __future__ import annotations

import asyncio

from samples.shared import print_header


async def demo_context_provider_vector() -> None:
    """Demo: Neo4j Context Provider with vector search."""
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

    print_header("Demo: Context Provider (Vector Search)")
    print("This demo shows the Neo4jContextProvider enhancing ChatAgent")
    print("responses with semantic search using neo4j-graphrag retrievers.\n")

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
    print(f"Embedding Model: {azure_settings.embedding_model}\n")

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

        # Create context provider with vector search
        provider = Neo4jContextProvider(
            uri=neo4j_settings.uri,
            username=neo4j_settings.username,
            password=neo4j_settings.get_password(),
            index_name=neo4j_settings.vector_index_name,
            index_type="vector",
            embedder=embedder,
            top_k=5,
            context_prompt=(
                "## Semantic Search Results\n"
                "Use the following semantically relevant information from the "
                "knowledge graph to answer questions:"
            ),
        )

        # Create agent client
        client = create_agent_client(agent_config, credential)

        # Use both provider and agent as async context managers
        async with provider:
            print("Connected to Neo4j!\n")

            async with client.create_agent(
                name=agent_config.name,
                instructions=(
                    "You are a helpful assistant that answers questions about companies "
                    "using the provided semantic search context. Be concise and accurate. "
                    "When the context contains relevant information, cite it in your response."
                ),
                context_provider=provider,
            ) as agent:
                print("Agent created with vector context provider!\n")
                print("-" * 50)

                # Demo queries - semantic search finds conceptually similar content
                queries = [
                    "What are the main business activities of tech companies?",
                    "Describe challenges and risks in the technology sector",
                    "How do companies generate revenue and measure performance?",
                ]

                for i, query in enumerate(queries, 1):
                    print(f"\n[Query {i}] User: {query}\n")

                    response = await agent.run(query)
                    print(f"[Query {i}] Agent: {response.text}\n")
                    print("-" * 50)

                print(
                    "\nDemo complete! Vector search found semantically similar content "
                    "to enhance agent responses."
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
