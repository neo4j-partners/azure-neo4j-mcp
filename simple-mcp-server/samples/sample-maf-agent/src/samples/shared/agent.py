"""
Agent management module using Microsoft Agent Framework with Microsoft Foundry.

This module provides configuration and agent creation using the Microsoft Agent
Framework (2025) with Microsoft Foundry (V2 SDK - azure-ai-projects) integration
for persistent, service-managed agents.

BEST PRACTICE: Agent Creation Pattern
Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/foundry_agent/agent.py

The correct pattern for creating agents with Azure AI Foundry is:

    1. Create an AzureAIAgentClient with credential and endpoint
    2. Pass the client to ChatAgent as the chat_client parameter
    3. Use ChatAgent directly (not client.create_agent() which doesn't exist)

Example:
    chat_client = AzureAIAgentClient(
        project_endpoint=os.environ.get("AZURE_AI_PROJECT_ENDPOINT"),
        model_deployment_name=os.environ.get("AZURE_AI_MODEL_DEPLOYMENT_NAME"),
        credential=credential,
    )
    agent = ChatAgent(
        chat_client=chat_client,
        name="MyAgent",
        instructions="You are a helpful assistant.",
        tools=[my_tool],
    )

Note: The parameter is `credential`, not `async_credential`.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional

from agent_framework import ChatAgent
from agent_framework.azure import AzureAIAgentClient
from azure.identity.aio import AzureCliCredential

from .logging import get_logger

logger = get_logger()


# BEST PRACTICE: Dataclass Configuration Pattern
# Reference: Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/workflow.py
#
# Using @dataclass(slots=True) for configuration provides several benefits:
# 1. Memory efficiency: slots=True reduces memory overhead per instance
# 2. Immutability clarity: frozen=True can be added if config shouldn't change
# 3. Type hints: Clear documentation of expected types
# 4. Default values: Simple, readable default definitions
# 5. No magic: Unlike pydantic-settings, behavior is explicit and predictable
# 6. Testability: Easy to create test configurations without environment setup
#
# Environment variables are loaded via a factory function, keeping the dataclass
# pure and separating concerns between structure and loading logic.


@dataclass(slots=True)
class AgentConfig:
    """
    Agent configuration for Azure AI Foundry.

    BEST PRACTICE: Use dataclass for configuration structure.
    Reference: Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/workflow.py

    This dataclass defines the structure. Use load_agent_config() to create
    an instance from environment variables, or construct directly for testing.

    Attributes:
        name: Name of the agent
        model: Model deployment name (e.g., "gpt-4o")
        instructions: Default system instructions for the agent
        project_endpoint: Azure AI Foundry project endpoint URL
    """

    name: str = "api-arches-agent"
    model: str = "gpt-4o"
    instructions: str = "You are a helpful API assistant."
    project_endpoint: Optional[str] = None


@dataclass(slots=True)
class DemoConfig:
    """
    Runtime configuration for demo execution.

    BEST PRACTICE: Separate runtime options from service configuration.
    Reference: Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/workflow.py

    This dataclass contains options that affect demo behavior, not service connections.

    Attributes:
        debug: Enable verbose debug output
        streaming: Use streaming responses instead of blocking
        top_k: Number of results to retrieve from context providers
    """

    debug: bool = False
    streaming: bool = False
    top_k: int = 5


def load_agent_config() -> AgentConfig:
    """
    Load AgentConfig from environment variables.

    BEST PRACTICE: Factory function for environment loading.
    Reference: Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/cli.py

    This pattern separates:
    - Structure definition (dataclass) from loading logic (this function)
    - Makes testing easier: construct AgentConfig directly without env vars
    - Makes dependencies explicit: you can see exactly what env vars are used

    Environment Variables:
        AZURE_AI_AGENT_NAME: Agent name (default: "api-arches-agent")
        AZURE_AI_MODEL_NAME: Model deployment name (default: "gpt-4o")
        AZURE_AI_PROJECT_ENDPOINT: Azure AI Foundry project endpoint (required)

    Returns:
        AgentConfig instance populated from environment.
    """
    return AgentConfig(
        name=os.getenv("AZURE_AI_AGENT_NAME", "api-arches-agent"),
        model=os.getenv("AZURE_AI_MODEL_NAME", "gpt-4o"),
        project_endpoint=os.getenv("AZURE_AI_PROJECT_ENDPOINT"),
    )


def create_agent_client(config: AgentConfig, credential: AzureCliCredential) -> AzureAIAgentClient:
    """
    Create an AzureAIAgentClient configured for Foundry.

    The returned client can be passed to ChatAgent as the chat_client parameter.

    BEST PRACTICE: This function creates only the chat client, not the agent.
    Reference: Agent-Framework-Samples/08.EvaluationAndTracing/python/foundry_agent/agent.py

    The correct pattern separates client creation from agent creation:
    - AzureAIAgentClient: Handles communication with Azure AI Foundry
    - ChatAgent: Wraps the client with agent-specific configuration

    This separation allows:
    1. Reusing the same client for multiple agents
    2. Clear responsibility: client handles transport, agent handles behavior
    3. Easier testing: mock the client, test the agent logic

    Args:
        config: Agent configuration with project endpoint and model settings.
        credential: Azure CLI credential for authentication.

    Returns:
        Configured AzureAIAgentClient instance.
    """
    logger.info(f"Creating AzureAIAgentClient for project: {config.project_endpoint}")
    # Note: The parameter is `credential`, not `async_credential`
    # This was a common mistake from outdated documentation
    return AzureAIAgentClient(
        project_endpoint=config.project_endpoint,
        model_deployment_name=config.model,
        credential=credential,
    )


# Re-export for convenience - allows `from samples.shared import AgentConfig`
# without breaking existing imports that used the old pydantic-based class
__all__ = [
    "AgentConfig",
    "DemoConfig",
    "load_agent_config",
    "create_agent_client",
    "ChatAgent",
]
