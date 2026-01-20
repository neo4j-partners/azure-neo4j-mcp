"""
Neo4j MCP Tool-Calling LangGraph Agent

This agent connects to a Neo4j MCP server deployed on Azure Container Apps
via a Databricks Unity Catalog HTTP connection with bearer token authentication.

The connection is created in neo4j-mcp-http-connection.ipynb and uses secrets
configured by scripts/setup-databricks-secrets.sh.

Features:
- Connects to external Neo4j MCP server via Unity Catalog HTTP connection proxy
- Uses bearer token authentication from Databricks secrets
- Provides READ-ONLY access to Neo4j (get-schema, read-cypher tools)
- Compatible with MLflow ResponsesAgent for deployment

Prerequisites:
- HTTP connection created: neo4j_azure_beta_mcp (see neo4j-mcp-http-connection.ipynb)
- Secrets configured in scope: mcp-neo4j-secrets (see setup-databricks-secrets.sh)
- "Is MCP connection" checkbox enabled in Catalog Explorer
"""

import asyncio
from typing import Annotated, Any, AsyncGenerator, Generator, Optional, Sequence, TypedDict, Union
import json

import mlflow
import nest_asyncio
from databricks.sdk import WorkspaceClient
from databricks_langchain import (
    ChatDatabricks,
    DatabricksMCPServer,
    DatabricksMultiServerMCPClient,
)
from langchain.messages import AIMessage, AIMessageChunk, AnyMessage
from langchain_core.language_models import LanguageModelLike
from langchain_core.runnables import RunnableConfig, RunnableLambda
from langchain_core.tools import BaseTool
from langgraph.graph import END, StateGraph
from langgraph.graph.message import add_messages
from langgraph.prebuilt.tool_node import ToolNode
from mlflow.pyfunc import ResponsesAgent
from mlflow.types.responses import (
    ResponsesAgentRequest,
    ResponsesAgentResponse,
    ResponsesAgentStreamEvent,
    output_to_responses_items_stream,
    to_chat_completions_input,
)
from langchain_core.messages.tool import ToolMessage

nest_asyncio.apply()

############################################
# Configuration
############################################

# LLM endpoint - using Claude on Databricks
LLM_ENDPOINT_NAME = "databricks-claude-3-7-sonnet"
llm = ChatDatabricks(endpoint=LLM_ENDPOINT_NAME)

# Unity Catalog HTTP connection name for Neo4j MCP
# This connection is created by neo4j-mcp-http-connection.ipynb
CONNECTION_NAME = "neo4j_azure_beta_mcp"

# Databricks secrets scope for MCP credentials
# Configured by scripts/setup-databricks-secrets.sh
SECRET_SCOPE = "mcp-neo4j-secrets"

# System prompt for the Neo4j graph assistant
system_prompt = """
You are a helpful assistant that can query a Neo4j graph database.

You have access to the following tools:
- get-schema: Retrieve the database schema including node labels, relationship types, and properties
- read-cypher: Execute read-only Cypher queries against the database

When users ask questions about the data:
1. First use get-schema if you need to understand the database structure
2. Then construct and execute appropriate Cypher queries using read-cypher
3. Explain the results clearly to the user

IMPORTANT: You can only read data. Write operations are not permitted.
Always use valid Cypher syntax and handle query results appropriately.
"""

############################################
# Workspace Client and MCP Server Setup
############################################

# Initialize workspace client for Databricks API access
workspace_client = WorkspaceClient()
host = workspace_client.config.host

# External MCP server URL format for Unity Catalog HTTP connections
# The proxy endpoint handles authentication using the connection's bearer token
external_mcp_url = f"{host}/api/2.0/mcp/external/{CONNECTION_NAME}"

# Configure MCP client to connect through the Unity Catalog HTTP connection proxy
# This routes requests through the HTTP connection which uses bearer token auth
databricks_mcp_client = DatabricksMultiServerMCPClient(
    [
        DatabricksMCPServer(
            name="neo4j-mcp",
            url=external_mcp_url,
            workspace_client=workspace_client,
        ),
    ]
)


############################################
# Agent State and Graph Definition
############################################

class AgentState(TypedDict):
    """State for the agent workflow."""
    messages: Annotated[Sequence[AnyMessage], add_messages]
    custom_inputs: Optional[dict[str, Any]]
    custom_outputs: Optional[dict[str, Any]]


def create_tool_calling_agent(
    model: LanguageModelLike,
    tools: Union[ToolNode, Sequence[BaseTool]],
    system_prompt: Optional[str] = None,
):
    """
    Create a LangGraph tool-calling agent workflow.

    Args:
        model: The language model to use
        tools: Tools available to the agent
        system_prompt: Optional system prompt to prepend to messages

    Returns:
        Compiled LangGraph workflow
    """
    model = model.bind_tools(tools)

    def should_continue(state: AgentState):
        """Check if agent should continue or finish based on last message."""
        messages = state["messages"]
        last_message = messages[-1]
        if isinstance(last_message, AIMessage) and last_message.tool_calls:
            return "continue"
        return "end"

    # Preprocess: optionally prepend system prompt
    if system_prompt:
        preprocessor = RunnableLambda(
            lambda state: [{"role": "system", "content": system_prompt}] + state["messages"]
        )
    else:
        preprocessor = RunnableLambda(lambda state: state["messages"])

    model_runnable = preprocessor | model

    def call_model(state: AgentState, config: RunnableConfig):
        """Invoke the model within the workflow."""
        response = model_runnable.invoke(state, config)
        return {"messages": [response]}

    # Build the agent graph
    workflow = StateGraph(AgentState)
    workflow.add_node("agent", RunnableLambda(call_model))
    workflow.add_node("tools", ToolNode(tools))

    workflow.set_entry_point("agent")
    workflow.add_conditional_edges(
        "agent",
        should_continue,
        {
            "continue": "tools",
            "end": END,
        },
    )
    workflow.add_edge("tools", "agent")

    return workflow.compile()


############################################
# ResponsesAgent Wrapper
############################################

class LangGraphResponsesAgent(ResponsesAgent):
    """
    ResponsesAgent wrapper for LangGraph workflows.

    Makes the LangGraph agent compatible with Mosaic AI Responses API
    for deployment and evaluation.
    """

    def __init__(self, agent):
        self.agent = agent

    def predict(self, request: ResponsesAgentRequest) -> ResponsesAgentResponse:
        """Make a single prediction."""
        outputs = [
            event.item
            for event in self.predict_stream(request)
            if event.type == "response.output_item.done" or event.type == "error"
        ]
        return ResponsesAgentResponse(output=outputs, custom_outputs=request.custom_inputs)

    async def _predict_stream_async(
        self,
        request: ResponsesAgentRequest,
    ) -> AsyncGenerator[ResponsesAgentStreamEvent, None]:
        """Async streaming prediction."""
        cc_msgs = to_chat_completions_input([i.model_dump() for i in request.input])

        async for event in self.agent.astream(
            {"messages": cc_msgs}, stream_mode=["updates", "messages"]
        ):
            if event[0] == "updates":
                for node_data in event[1].values():
                    if len(node_data.get("messages", [])) > 0:
                        all_messages = []
                        for msg in node_data["messages"]:
                            if isinstance(msg, ToolMessage) and not isinstance(msg.content, str):
                                msg.content = json.dumps(msg.content)
                            all_messages.append(msg)
                        for item in output_to_responses_items_stream(all_messages):
                            yield item
            elif event[0] == "messages":
                try:
                    chunk = event[1][0]
                    if isinstance(chunk, AIMessageChunk) and (content := chunk.content):
                        yield ResponsesAgentStreamEvent(
                            **self.create_text_delta(delta=content, item_id=chunk.id),
                        )
                except:
                    pass

    def predict_stream(
        self, request: ResponsesAgentRequest
    ) -> Generator[ResponsesAgentStreamEvent, None, None]:
        """Stream predictions, yielding output as it's generated."""
        agen = self._predict_stream_async(request)

        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

        ait = agen.__aiter__()

        while True:
            try:
                item = loop.run_until_complete(ait.__anext__())
            except StopAsyncIteration:
                break
            else:
                yield item


############################################
# Agent Initialization
############################################

def initialize_agent():
    """
    Initialize the Neo4j MCP agent with tools from the HTTP connection.

    Returns:
        LangGraphResponsesAgent: The initialized agent ready for predictions
    """
    # Get MCP tools from the configured Neo4j server
    mcp_tools = asyncio.run(databricks_mcp_client.get_tools())

    print(f"Loaded {len(mcp_tools)} tools from Neo4j MCP server:")
    for tool in mcp_tools:
        print(f"  - {tool.name}: {tool.description[:60]}...")

    # Create the agent graph
    agent = create_tool_calling_agent(llm, mcp_tools, system_prompt)
    return LangGraphResponsesAgent(agent)


# Enable MLflow autologging for tracing
mlflow.langchain.autolog()

# Initialize the agent
AGENT = initialize_agent()

# Set as the MLflow model
mlflow.models.set_model(AGENT)
