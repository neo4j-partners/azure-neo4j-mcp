# Improvement Suggestions for sample-maf-agent

This document identifies opportunities to align the sample-maf-agent code with best practices from the [Microsoft Agent Framework Samples](https://github.com/Azure/Agent-Framework-Samples) repository.

## Summary of Recent Fixes

The following issues were fixed to align with the correct API:

1. **Changed `AzureAIClient` to `AzureAIAgentClient`** - The correct class from `agent_framework.azure`
2. **Removed non-existent `client.create_agent()` pattern** - Replaced with direct `ChatAgent` instantiation
3. **Fixed credential parameter name** - Changed `async_credential` to `credential` per API signature
4. **Updated all demo files** - vector_search, basic_fulltext, graph_enriched, mcp_tools

## High Priority Improvements - IMPLEMENTED

The following high-priority improvements have been implemented with detailed comments explaining the best practices:

### 1. Grouped Async Context Managers ✅

All demo files now use `async with (resource1, resource2, ...):` pattern with comments explaining:
- Automatic cleanup without manual finally blocks
- No asyncio.sleep() workarounds needed
- Clear resource lifetime and proper ordering

### 2. Thread Management for Conversations ✅

All demo files now use `agent.get_new_thread()` with comments explaining:
- Conversation history preservation
- Context maintained across queries
- Session isolation benefits

### 3. MCP_AGENT.md Updated ✅

All code examples updated to use the correct API pattern.

### 4. Best Practice Comments Added ✅

Each implementation includes reference comments pointing to the official Agent-Framework-Samples files.

---

## High Priority Improvements

### 1. Use Grouped Async Context Managers for Resource Cleanup

**Current Pattern:**
```python
credential = AzureCliCredential()
embedder = None
try:
    embedder = AzureAIEmbedder(...)
    # ... use resources
finally:
    if embedder is not None:
        embedder.close()
    await credential.close()
    await asyncio.sleep(0.1)  # Workaround for cleanup
```

**Best Practice (from `tracer_aspire/simple.py`):**
```python
async with (
    AzureCliCredential() as credential,
    AIProjectClient(endpoint=..., credential=credential) as project,
    AzureAIAgentClient(project_client=project) as client,
):
    agent = ChatAgent(chat_client=client, ...)
    # Resources automatically cleaned up
```

**Benefits:**
- No manual cleanup required
- No `asyncio.sleep()` workarounds
- Cleaner exception handling
- Resources properly closed even on errors

**Files to Update:**
- `src/samples/vector_search/main.py`
- `src/samples/graph_enriched/main.py`
- `src/samples/basic_fulltext/main.py`
- `src/samples/mcp_tools/main.py`

---

### 2. Add Thread Management for Multi-Turn Conversations

**Current Pattern:**
```python
for query in queries:
    response = await agent.run(query)  # No thread - each query is independent
```

**Best Practice (from `tracer_aspire/simple.py`):**
```python
thread = agent.get_new_thread()
for query in queries:
    response = await agent.run(query, thread=thread)  # Conversation history preserved
```

**Benefits:**
- Agent remembers previous queries in the conversation
- More realistic demo of conversational AI
- Enables follow-up questions

**Files to Update:**
- All demo files should use explicit threads when running multiple queries

---

### 3. Update MCP_AGENT.md Proposal with Correct API

The proposal document `MCP_AGENT.md` contains outdated code examples that use the non-existent API:

**Outdated Code in MCP_AGENT.md (lines 196-210):**
```python
# INCORRECT - This API does not exist
async with (
    AzureAIAgentClient(async_credential=credential).create_agent(
        name="Neo4jAgent",
        instructions="...",
        tools=MCPStreamableHTTPTool(...),
    ) as agent,
):
```

**Should Be:**
```python
async with (
    AzureCliCredential() as credential,
    MCPStreamableHTTPTool(...) as mcp_tool,
):
    chat_client = AzureAIAgentClient(
        project_endpoint=os.environ.get("AZURE_AI_PROJECT_ENDPOINT"),
        model_deployment_name=os.environ.get("AZURE_AI_MODEL_DEPLOYMENT_NAME"),
        credential=credential,
    )
    agent = ChatAgent(
        name="Neo4jAgent",
        chat_client=chat_client,
        instructions="...",
        tools=mcp_tool,
    )
```

---

## Medium Priority Improvements

### 4. Add OpenTelemetry Observability Support

**Current State:** Basic Python logging only

**Best Practice (from `GHModel.Python.AI.Workflow.OpenTelemetry/main.py`):**
```python
from agent_framework.observability import configure_otel_providers, get_tracer
from opentelemetry.trace import SpanKind
from opentelemetry.trace.span import format_trace_id

async def main():
    configure_otel_providers()

    with get_tracer().start_as_current_span("Demo Span", kind=SpanKind.CLIENT) as span:
        print(f"Trace ID: {format_trace_id(span.get_span_context().trace_id)}")
        response = await agent.run(query)
```

**Implementation:**
1. Add optional `--trace` flag to CLI
2. Configure OTLP exporter when tracing enabled
3. Wrap demo execution in spans
4. Print trace IDs for debugging

**Add to `pyproject.toml`:**
```toml
[project.optional-dependencies]
tracing = [
    "opentelemetry-exporter-otlp>=1.20.0",
]
```

---

### 5. Add DevUI Support for Interactive Debugging

**Best Practice (from `foundry_agent/agent.py`):**
```python
from agent_framework.devui import serve

def main():
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    logger = logging.getLogger(__name__)

    logger.info("Starting Agent")
    logger.info("Available at: http://localhost:8090")

    serve(entities=[agent], port=8090, auto_open=True)
```

**Implementation:**
1. Add `devui` command to CLI: `uv run start-samples devui`
2. Create module-level agent instances that can be served
3. Add `agent_framework.devui` to optional dependencies

**Benefits:**
- Visual debugging interface
- Interactive testing
- Real-time conversation history

---

### 6. Add Streaming Response Support

**Current Pattern:**
```python
response = await agent.run(query)
print(f"Agent: {response.text}")
```

**Best Practice (from `tracer_aspire/simple.py`):**
```python
print(f"{agent.display_name}: ", end="")
async for update in agent.run_stream(query, thread=thread):
    if update.text:
        print(update.text, end="", flush=True)
print()  # Newline after streaming complete
```

**Benefits:**
- Better user experience (see response as it generates)
- Demonstrates streaming API
- More realistic production pattern

**Implementation:**
- Add `--stream` flag to CLI
- Use `run_stream()` instead of `run()` when enabled

---

### 7. Enhanced Error Handling with Graceful Degradation

**Current Pattern:**
```python
except Exception as e:
    logger.error(f"Error during demo: {e}")
    print(f"\nError: {e}")
    raise
```

**Best Practice (from `tools.py` TavilySearchTools):**
```python
def _do_search(self, query: str, ...) -> dict[str, Any]:
    try:
        # ... perform search
        return {"query": query, "results": results}
    except Exception as e:
        # Return error info instead of raising
        error_msg = str(e)
        if len(error_msg) > 300:
            error_msg = error_msg[:300] + "..."
        return {
            "query": query,
            "error": f"Search failed: {error_msg}",
            "results": [],
        }
```

**Benefits:**
- Agent can handle errors gracefully
- Demo continues even with partial failures
- Better error messages for users

---

### 8. Add CLI Argument Support for Provider Selection

**Best Practice (from `AgenticMarketingContentGen/cli.py`):**
```python
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Neo4j MAF Provider Demo")
    parser.add_argument("--provider", choices=["azure", "github", "openai"], default="azure")
    parser.add_argument("--model-id", dest="model_id", help="Model ID override")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    parser.add_argument("--stream", action="store_true", help="Enable streaming responses")
    return parser.parse_args()

def _build_chat_client(args: argparse.Namespace) -> Any:
    if args.provider == "azure":
        return AzureAIAgentClient(...)
    elif args.provider == "github":
        return OpenAIChatClient(
            base_url=os.environ.get("GITHUB_ENDPOINT"),
            api_key=os.environ.get("GITHUB_TOKEN"),
            model_id=os.environ.get("GITHUB_MODEL_ID"),
        )
```

**Implementation:**
- Update `cli.py` to support provider selection
- Add `--model`, `--debug`, `--stream` flags
- Allow overriding environment-based configuration

---

## Lower Priority Improvements

### 9. Add Simple Test Scripts

**Best Practice (from `test_simple.py`):**
```python
#!/usr/bin/env python3
"""Simple test script for workflow validation."""

import logging
import os
from dotenv import load_dotenv

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

load_dotenv()

def main():
    try:
        # Test agent creation
        agent = ChatAgent(...)
        logger.info("Agent created successfully")

        # Test simple query
        response = await agent.run("Hello")
        logger.info(f"Response: {response.text}")

    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)
        raise

if __name__ == "__main__":
    main()
```

**Implementation:**
- Add `tests/` directory
- Create `test_agent_creation.py`
- Create `test_context_provider.py`
- Add `pytest` to dev dependencies

---

### 10. Use Dataclass Configuration Pattern

**Current Pattern:** Pydantic BaseSettings (good, but verbose)

**Alternative Best Practice (from `workflow.py`):**
```python
from dataclasses import dataclass
from typing import Optional, Mapping, Any

@dataclass(slots=True)
class DemoConfig:
    """Runtime configuration for demos."""

    enable_streaming: bool = False
    enable_tracing: bool = False
    debug: bool = False
    top_k: int = 5
    provider: str = "azure"
```

**Note:** Current Pydantic-based approach is also valid and provides automatic validation. Consider this only if simplification is desired.

---

### 11. Add `@ai_function` Decorator for Custom Tools

If adding custom tools to demos, use the decorator pattern:

**Best Practice:**
```python
from agent_framework import ai_function
from typing import Annotated

@ai_function(description="Search the Neo4j knowledge graph for information")
def search_knowledge_graph(
    query: Annotated[str, "The search query to find relevant information"],
    top_k: Annotated[int, "Maximum number of results to return"] = 5,
) -> dict[str, Any]:
    """Search the knowledge graph and return relevant results."""
    # Implementation
    return {"query": query, "results": [...]}
```

---

## File-Specific Recommendations

### `src/samples/shared/agent.py`

1. Consider adding the `ChatAgent` class to the return type hint:
   ```python
   def create_chat_agent(
       config: AgentConfig,
       credential: AzureCliCredential,
       **kwargs: Any,
   ) -> ChatAgent:
   ```

2. Add helper for creating agents with context providers:
   ```python
   def create_agent_with_context(
       config: AgentConfig,
       credential: AzureCliCredential,
       context_providers: ContextProvider | list[ContextProvider],
       instructions: str,
   ) -> ChatAgent:
   ```

### `src/samples/shared/cli.py`

1. Add global flags: `--debug`, `--stream`, `--trace`
2. Add provider selection: `--provider azure|github|openai`
3. Consider removing `[NOT WORKING]` from menu - either fix or remove demo 2

### `src/samples/vector_search/main.py`

1. Use grouped async context managers
2. Add thread for multi-turn conversation
3. Add optional streaming support
4. Consider removing `asyncio.sleep(0.1)` workaround

---

## Implementation Priority

| Priority | Item | Effort | Impact |
|----------|------|--------|--------|
| High | Grouped async context managers | Low | High |
| High | Thread management for conversations | Low | Medium |
| High | Update MCP_AGENT.md proposal | Low | Medium |
| Medium | OpenTelemetry support | Medium | Medium |
| Medium | DevUI support | Medium | High |
| Medium | Streaming responses | Low | Medium |
| Medium | Enhanced error handling | Low | Medium |
| Medium | CLI argument support | Medium | Medium |
| Low | Test scripts | Medium | Medium |
| Low | Dataclass configuration | Low | Low |

---

## References

- [Agent-Framework-Samples Repository](https://github.com/Azure/Agent-Framework-Samples)
- [08.EvaluationAndTracing/python/foundry_agent/agent.py](../../Agent-Framework-Samples/08.EvaluationAndTracing/python/foundry_agent/agent.py) - Agent creation pattern
- [09.Cases/AgenticMarketingContentGen/marketing_workflow/](../../Agent-Framework-Samples/09.Cases/AgenticMarketingContentGen/marketing_workflow/) - Advanced patterns
- [08.EvaluationAndTracing/python/tracer_aspire/simple.py](../../Agent-Framework-Samples/08.EvaluationAndTracing/python/tracer_aspire/simple.py) - Async context managers and tracing
