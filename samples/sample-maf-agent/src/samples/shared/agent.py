"""
Agent management module using Microsoft Agent Framework with Microsoft Foundry.

This module provides configuration and agent creation using the Microsoft Agent
Framework (2025) with Microsoft Foundry (V2 SDK - azure-ai-projects) integration
for persistent, service-managed agents.
"""

from agent_framework.azure import AzureAIClient
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


def create_agent_client(config: AgentConfig, credential: AzureCliCredential) -> AzureAIClient:
    """
    Create an AzureAIClient configured for Foundry.

    The returned client should be used as an async context manager to create agents.

    Args:
        config: Agent configuration with project endpoint and model settings.
        credential: Azure CLI credential for authentication.

    Returns:
        Configured AzureAIClient instance.
    """
    client_kwargs = {"credential": credential}

    if config.project_endpoint:
        client_kwargs["project_endpoint"] = config.project_endpoint

    if config.model:
        client_kwargs["model_deployment_name"] = config.model

    logger.info(f"Creating AzureAIClient for project: {config.project_endpoint}")
    return AzureAIClient(**client_kwargs)


