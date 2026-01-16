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
    from samples.shared import AgentConfig, create_agent_client, get_logger

    logger = get_logger()

    print_header("Demo: Context Provider (Fulltext Search)")
    print("This demo shows the Neo4jContextProvider enhancing ChatAgent")
    print("responses with knowledge graph context using fulltext search.\n")

    # Load configs
    agent_config = AgentConfig()
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

    credential = AzureCliCredential()

    try:
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

        # Create agent client
        client = create_agent_client(agent_config, credential)

        # Use both provider and agent as async context managers
        async with provider:
            print("Connected to Neo4j!\n")

            async with client.create_agent(
                name=agent_config.name,
                instructions=(
                    "You are a helpful assistant that answers questions about companies "
                    "using the provided knowledge graph context. Be concise and cite "
                    "specific information from the context when available."
                ),
                context_provider=provider,
            ) as agent:
                print("Agent created with context provider!\n")
                print("-" * 50)

                # Demo queries that will trigger context retrieval
                queries = [
                    "What products does Microsoft offer?",
                    "Tell me about risk factors for technology companies",
                    "What are some financial metrics mentioned in SEC filings?",
                ]

                for i, query in enumerate(queries, 1):
                    print(f"\n[Query {i}] User: {query}\n")

                    response = await agent.run(query)
                    print(f"[Query {i}] Agent: {response.text}\n")
                    print("-" * 50)

                print(
                    "\nDemo complete! The context provider enriched agent responses "
                    "with knowledge graph data."
                )

    except ConnectionError as e:
        print(f"\nConnection Error: {e}")
        print("Please check your Neo4j configuration.")
    except Exception as e:
        logger.error(f"Error during demo: {e}")
        print(f"\nError: {e}")
        raise
    finally:
        await credential.close()
