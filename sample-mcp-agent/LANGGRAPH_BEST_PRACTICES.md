# LangGraph Best Practices Guide

> Last updated: January 2026

This document captures best practices for building agents with LangGraph and LangChain, based on the latest stable releases and official documentation.

## Latest Versions

| Package | Version | Release Date |
|---------|---------|--------------|
| langgraph | 1.0.6 | January 12, 2026 |
| langgraph-prebuilt | 1.0.6 | January 2026 |
| langchain | 1.2.4 | January 14, 2026 |
| langchain-mcp-adapters | 0.1.0+ | 2025 |

**Requirements:** Python 3.10+

## API Migration: LangGraph v1

### Deprecated Import (will be removed in v2.0)

```python
# DEPRECATED - do not use
from langgraph.prebuilt import create_react_agent

agent = create_react_agent(
    model,
    tools,
    prompt="You are a helpful assistant",  # 'prompt' parameter
)
```

### Recommended Import (LangChain v1+)

```python
# RECOMMENDED - use this
from langchain.agents import create_agent

agent = create_agent(
    model,
    tools,
    system_prompt="You are a helpful assistant",  # 'system_prompt' parameter
)
```

**Key differences:**
- Function renamed from `create_react_agent` to `create_agent`
- Parameter renamed from `prompt` to `system_prompt`
- New middleware system for extensibility

## Creating Agents

### Basic Agent Setup

```python
from langchain.agents import create_agent
from langchain_aws import ChatBedrockConverse

# Initialize the LLM
llm = ChatBedrockConverse(
    model="us.anthropic.claude-sonnet-4-20250514-v1:0",
    region_name="us-west-2",
    temperature=0,
)

# Create the agent
agent = create_agent(
    llm,
    tools,
    system_prompt="You are a helpful assistant with access to database tools.",
)

# Run the agent
result = await agent.ainvoke({"messages": [("user", "What data do you have?")]})
```

### Function Signature (create_agent)

```python
create_agent(
    model: str | BaseChatModel,
    tools: Sequence[BaseTool | Callable | dict] | None = None,
    *,
    system_prompt: str | SystemMessage | None = None,
    middleware: Sequence[AgentMiddleware] = (),
    response_format: ResponseFormat | type | None = None,
    state_schema: type[AgentState] | None = None,
    context_schema: type | None = None,
    checkpointer: Checkpointer | None = None,
    store: BaseStore | None = None,
    interrupt_before: list[str] | None = None,
    interrupt_after: list[str] | None = None,
    debug: bool = False,
    name: str | None = None,
    cache: BaseCache | None = None,
) -> CompiledStateGraph
```

### Function Signature (create_react_agent - deprecated)

If you must use the deprecated API:

```python
from langgraph.prebuilt import create_react_agent

create_react_agent(
    model: str | LanguageModelLike | Callable,
    tools: Sequence[BaseTool | Callable | dict] | ToolNode,
    *,
    prompt: Prompt | None = None,  # Note: 'prompt', not 'system_prompt'
    response_format: StructuredResponseSchema | None = None,
    pre_model_hook: RunnableLike | None = None,
    post_model_hook: RunnableLike | None = None,
    state_schema: type | None = None,
    context_schema: type | None = None,
    checkpointer: Checkpointer | None = None,
    store: BaseStore | None = None,
    interrupt_before: list[str] | None = None,
    interrupt_after: list[str] | None = None,
    debug: bool = False,
    version: Literal["v1", "v2"] = "v2",
    name: str | None = None,
) -> CompiledStateGraph
```

## MCP Client Integration

### langchain-mcp-adapters 0.1.0+

The MCP adapters API changed in version 0.1.0. Context managers are no longer supported.

```python
# OLD WAY - no longer works
async with MultiServerMCPClient(config) as client:
    tools = client.get_tools()

# NEW WAY - use this
client = MultiServerMCPClient(config)
tools = await client.get_tools()  # Note: now async
```

### Complete MCP Example

```python
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain.agents import create_agent

client = MultiServerMCPClient(
    {
        "neo4j": {
            "transport": "streamable_http",
            "url": "https://your-mcp-server.com/mcp",
            "headers": {
                "Authorization": "Bearer YOUR_API_KEY",
            },
        }
    }
)

# Get tools (async, no context manager)
tools = await client.get_tools()

# Create agent with tools
agent = create_agent(
    llm,
    tools,
    system_prompt="You are a database assistant.",
)

# Run
result = await agent.ainvoke({"messages": [("user", question)]})
```

## Key Features (LangGraph 1.0)

### Durable Execution
Build agents that persist through failures and automatically resume from where they stopped.

### Human-in-the-Loop
Incorporate human oversight by inspecting and modifying agent state at any point:

```python
agent = create_agent(
    llm,
    tools,
    interrupt_before=["tools"],  # Pause before tool execution
)
```

### Memory Support
- **Short-term:** Working memory for ongoing reasoning
- **Long-term:** Persistent memory across sessions via `store` parameter

### Middleware (New in v1)
Inject logic before/after model calls and tool executions:

```python
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware

agent = create_agent(
    llm,
    tools,
    middleware=[HumanInTheLoopMiddleware()],
)
```

### Structured Output
Force specific output formats:

```python
from pydantic import BaseModel

class QueryResult(BaseModel):
    answer: str
    confidence: float
    sources: list[str]

agent = create_agent(
    llm,
    tools,
    response_format=QueryResult,
)
```

## Best Practices

### 1. Use the New API
Always prefer `langchain.agents.create_agent` over `langgraph.prebuilt.create_react_agent` for new projects.

### 2. Explicit System Prompts
Provide clear, detailed system prompts that define the agent's role and constraints:

```python
SYSTEM_PROMPT = """You are a database assistant with access to Neo4j tools.

Your capabilities:
- Retrieve database schema
- Execute read-only Cypher queries
- DO NOT execute write queries

When answering:
1. First check the schema
2. Formulate appropriate queries
3. Format results clearly
"""
```

### 3. Handle Async Properly
LangGraph agents are async-first:

```python
import asyncio

async def main():
    result = await agent.ainvoke({"messages": [("user", question)]})
    return result

asyncio.run(main())
```

### 4. Use Checkpointing for Long-Running Agents

```python
from langgraph.checkpoint.memory import MemorySaver

checkpointer = MemorySaver()
agent = create_agent(
    llm,
    tools,
    checkpointer=checkpointer,
)
```

### 5. Version Pin Dependencies
In production, pin to specific versions:

```toml
[project]
dependencies = [
    "langgraph>=1.0.5",
    "langchain>=1.2.0",
    "langchain-mcp-adapters>=0.1.0",
]
```

## When to Use What

| Use Case | Recommendation |
|----------|----------------|
| Quick prototyping | `create_agent` from `langchain.agents` |
| Simple ReAct agents | `create_agent` from `langchain.agents` |
| Custom workflows | Build with `langgraph.graph.StateGraph` |
| Heavy customization | Custom ReAct from scratch with LangGraph |
| Production deployments | LangGraph with checkpointing + LangSmith |

## Common Pitfalls

### 1. Wrong Import After Migration
```python
# This will fail - function was renamed
from langchain.agents import create_react_agent  # WRONG

# Correct import
from langchain.agents import create_agent  # RIGHT
```

### 2. Using 'prompt' Instead of 'system_prompt'
```python
# This will fail with create_agent
agent = create_agent(llm, tools, prompt="...")  # WRONG

# Correct parameter name
agent = create_agent(llm, tools, system_prompt="...")  # RIGHT
```

### 3. Using Context Manager with MCP Client
```python
# No longer supported in langchain-mcp-adapters 0.1.0+
async with client:  # WRONG
    tools = client.get_tools()

# Correct approach
tools = await client.get_tools()  # RIGHT
```

### 4. Forgetting Async
```python
# Will return a coroutine, not results
result = agent.ainvoke(...)  # WRONG

# Must await
result = await agent.ainvoke(...)  # RIGHT
```

## Sources and References

- [LangGraph PyPI](https://pypi.org/project/langgraph/) - Latest releases and changelog
- [LangGraph Prebuilt PyPI](https://pypi.org/project/langgraph-prebuilt/) - Prebuilt components
- [LangChain PyPI](https://pypi.org/project/langchain/) - LangChain framework
- [LangGraph Agents Reference](https://reference.langchain.com/python/langgraph/agents/) - API documentation
- [LangChain Agents Docs](https://docs.langchain.com/oss/python/langchain/agents) - Agent concepts and guides
- [ReAct Agent How-To](https://langchain-ai.github.io/langgraph/how-tos/react-agent-from-scratch/) - Building from scratch
- [LangGraph v1 Migration Guide](https://docs.langchain.com/oss/python/migrate/langgraph-v1) - Migration instructions
- [GitHub Issue #6404](https://github.com/langchain-ai/langgraph/issues/6404) - Deprecation message clarification
- [LangGraph React Agent Template](https://github.com/langchain-ai/react-agent) - Official template
