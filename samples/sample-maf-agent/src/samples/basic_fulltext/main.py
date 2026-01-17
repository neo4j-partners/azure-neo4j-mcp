"""
Demo: Neo4j Context Provider with ChatAgent (Fulltext Search).

Shows how the context provider enhances agent responses with
knowledge graph data using fulltext search.
"""

from __future__ import annotations

from samples.shared import print_header


async def demo_context_provider_basic() -> None:
    """Demo: Neo4j Context Provider with ChatAgent using fulltext search."""
    from azure.identity.aio import AzureCliCredential

    from agent_framework_neo4j import Neo4jContextProvider, Neo4jSettings
    from samples.shared import ChatAgent, create_agent_client, get_logger, load_agent_config

    logger = get_logger()

    print_header("Demo: Context Provider (Fulltext Search)")
    print("This demo shows the Neo4jContextProvider enhancing ChatAgent")
    print("responses with knowledge graph context using fulltext search.\n")

    # BEST PRACTICE: Use factory function to load config from environment
    # Reference: Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/cli.py
    agent_config = load_agent_config()
    neo4j_settings = Neo4jSettings()

    if not agent_config.project_endpoint:
        print("Error: AZURE_AI_PROJECT_ENDPOINT not configured.")
        return

    if not neo4j_settings.is_configured:
        print("Error: Neo4j not configured.")
        print("Required: NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD")
        return

    print(f"Agent: {agent_config.name}")
    print(f"Model: {agent_config.model}")
    print(f"Neo4j URI: {neo4j_settings.uri}")
    print(f"Fulltext Index: {neo4j_settings.fulltext_index_name}\n")

    # Create context provider with fulltext search
    provider = Neo4jContextProvider(
        uri=neo4j_settings.uri,
        username=neo4j_settings.username,
        password=neo4j_settings.get_password(),
        index_name=neo4j_settings.fulltext_index_name,
        index_type="fulltext",
        top_k=3,
        context_prompt=(
            "## Knowledge Graph Context\n"
            "Use the following information from the knowledge graph "
            "to answer questions about companies, products, and financials:"
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

            try:
                agent = ChatAgent(
                    name=agent_config.name,
                    chat_client=chat_client,
                    instructions=(
                        "You are a helpful assistant that answers questions about companies "
                        "using the provided knowledge graph context. Be concise and cite "
                        "specific information from the context when available."
                    ),
                    context_providers=provider,
                )
                print("Agent created with context provider!\n")
                print("-" * 50)

                # BEST PRACTICE: Thread Management for Multi-Turn Conversations
                # Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/tracer_aspire/simple.py
                #
                # Creating an explicit thread preserves conversation history, allowing
                # the agent to remember previous queries and build coherent responses.
                # Without a thread, each query is treated as an independent conversation.
                thread = agent.get_new_thread()

                # Demo queries that will trigger context retrieval
                queries = [
                    "What products does Microsoft offer?",
                    "Tell me about risk factors for technology companies",
                    "What are some financial metrics mentioned in SEC filings?",
                ]

                for i, query in enumerate(queries, 1):
                    print(f"\n[Query {i}] User: {query}\n")

                    # Pass the thread to maintain conversation context across queries
                    response = await agent.run(query, thread=thread)
                    print(f"[Query {i}] Agent: {response.text}\n")
                    print("-" * 50)

                print(
                    "\nDemo complete! The context provider enriched agent responses "
                    "with knowledge graph data."
                )

            finally:
                # IMPORTANT: Close the chat client to release aiohttp session
                # AzureAIAgentClient doesn't support async context manager,
                # so we must explicitly close it to avoid "Unclosed client session" warnings
                await chat_client.close()

    except ConnectionError as e:
        print(f"\nConnection Error: {e}")
        print("Please check your Neo4j configuration.")
    except Exception as e:
        logger.error(f"Error during demo: {e}")
        print(f"\nError: {e}")
        raise
