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

from agent_framework import ChatAgent
from agent_framework.azure import AzureAIAgentClient
from azure.identity.aio import AzureCliCredential
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from .logging import get_logger

logger = get_logger()


class AgentConfig(BaseSettings):
    """
    Agent configuration loaded from environment variables.

    Attributes:
        name: Name of the agent (AZURE_AI_AGENT_NAME)
        model: Model deployment name (AZURE_AI_MODEL_NAME)
        instructions: System instructions for the agent
        project_endpoint: Microsoft Foundry project endpoint (AZURE_AI_PROJECT_ENDPOINT)
    """

    model_config = SettingsConfigDict(
        env_prefix="",
        extra="ignore",
    )

    name: str = Field(
        default="api-arches-agent",
        validation_alias="AZURE_AI_AGENT_NAME",
    )
    model: str = Field(
        default="gpt-4o",
        validation_alias="AZURE_AI_MODEL_NAME",
    )
    instructions: str = Field(
        default="You are a helpful API assistant.",
    )
    project_endpoint: str | None = Field(
        default=None,
        validation_alias="AZURE_AI_PROJECT_ENDPOINT",
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


