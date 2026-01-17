"""
Demo: Neo4j Context Provider with Vector Search.

Shows semantic search using neo4j-graphrag VectorRetriever with
Azure AI embeddings and ChatAgent.
"""

from __future__ import annotations

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
    from samples.shared import AgentConfig, ChatAgent, create_agent_client, get_logger

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

    # Create sync credential for embedder (neo4j-graphrag uses sync APIs)
    sync_credential = DefaultAzureCredential()

    # Create embedder for neo4j-graphrag
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

    try:
        # BEST PRACTICE: Grouped Async Context Managers
        # Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/tracer_aspire/simple.py
        #
        # Using `async with (resource1, resource2, ...):` provides several benefits:
        # 1. Automatic cleanup: Resources are properly closed even if exceptions occur
        # 2. No manual finally blocks: Eliminates error-prone cleanup code
        # 3. No asyncio.sleep() workarounds: Context managers handle async cleanup timing
        # 4. Clear resource lifetime: Easy to see which resources are in scope
        # 5. Proper ordering: Resources are released in reverse order of acquisition
        async with (
            AzureCliCredential() as credential,
            provider,
        ):
            print("Connected to Neo4j!\n")

            # Create agent client and ChatAgent
            chat_client = create_agent_client(agent_config, credential)
            agent = ChatAgent(
                name=agent_config.name,
                chat_client=chat_client,
                instructions=(
                    "You are a helpful assistant that answers questions about companies "
                    "using the provided semantic search context. Be concise and accurate. "
                    "When the context contains relevant information, cite it in your response."
                ),
                context_providers=provider,
            )
            print("Agent created with vector context provider!\n")
            print("-" * 50)

            # BEST PRACTICE: Thread Management for Multi-Turn Conversations
            # Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/tracer_aspire/simple.py
            #
            # Creating an explicit thread provides:
            # 1. Conversation history: Agent remembers previous queries and responses
            # 2. Context preservation: Follow-up questions can reference earlier discussion
            # 3. Coherent dialogue: Agent can build on previous answers
            # 4. Session isolation: Different threads maintain separate conversations
            #
            # Without a thread, each query is treated as an independent conversation
            # and the agent has no memory of previous interactions.
            thread = agent.get_new_thread()

            # Demo queries - semantic search finds conceptually similar content
            queries = [
                "What are the main business activities of tech companies?",
                "Describe challenges and risks in the technology sector",
                "How do companies generate revenue and measure performance?",
            ]

            for i, query in enumerate(queries, 1):
                print(f"\n[Query {i}] User: {query}\n")

                # Pass the thread to maintain conversation context across queries
                response = await agent.run(query, thread=thread)
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
        # Close sync resources (embedder uses sync credential)
        embedder.close()
