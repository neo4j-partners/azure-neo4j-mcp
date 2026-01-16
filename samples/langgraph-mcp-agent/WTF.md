# WTF: OpenAI Schema Compatibility Investigation

## The Error

```
openai.BadRequestError: Error code: 400 - {'error': {'message': "Invalid schema for function
'get-schema': In context=(), object schema missing properties.", 'type': 'invalid_request_error',
'param': 'tools[0].function.parameters', 'code': 'invalid_function_parameters'}}
```

## Executive Summary

The original AWS sample works with **Claude on Bedrock**. When ported to **Azure OpenAI**, it fails because OpenAI has stricter JSON Schema requirements than Anthropic.

| Provider | Schema Requirement | `{"type": "object"}` alone |
|----------|-------------------|---------------------------|
| **Anthropic (Claude)** | Lenient | Accepted |
| **OpenAI (GPT-4)** | Strict | **REJECTED** - requires `properties` |

## Root Cause Analysis

### 1. The Neo4j MCP Server Tool Definitions

From `/Users/ryanknight/projects/mcp/internal/tools/cypher/get_schema_spec.go`:

```go
func GetSchemaSpec() mcp.Tool {
    return mcp.NewTool("get-schema",
        mcp.WithDescription(`Retrieve the schema information...`),
        // NOTE: No WithInputSchema[]() call - tool has NO parameters
    )
}
```

**Tools without parameters** (`get-schema`, `list-gds-procedures`) do NOT call `WithInputSchema[]()`.

### 2. The mcp-go Library Schema Generation

The [mcp-go library](https://github.com/mark3labs/mcp-go) generates tool schemas. When no input schema is specified, it should produce:

```json
{
  "type": "object",
  "properties": {}
}
```

**But the actual output appears to be:**

```json
{
  "type": "object"
}
```

This is the **exact same bug** reported in [github-mcp-server#1548](https://github.com/github/github-mcp-server/issues/1548):

> "The regression was introduced during a Go-SDK migration. The jsonschema library uses `omitempty` tags, causing empty maps to be omitted during JSON serialization."

### 3. The langchain-mcp-adapters Conversion

`langchain-mcp-adapters` converts MCP tools to LangChain `StructuredTool` objects:

```python
tools = await client.get_tools()  # Returns list of StructuredTool
```

The adapter passes through whatever schema the MCP server provides. It does **NOT** normalize schemas for OpenAI compatibility.

### 4. LangGraph's bind_tools()

From the [LangGraph docs](https://langchain-ai.github.io/langgraph/llms-full.txt):

> "The underlying `bind_tools()` method handles provider-specific schema transformations automatically."

**This is misleading.** LangGraph handles _format_ transformations (e.g., Anthropic's tool format vs OpenAI's function format), but it does **NOT** fix invalid schemas. If the input schema is `{"type": "object"}` without `properties`, it stays that way.

### 5. Why AWS Bedrock Works

The original sample uses:

```python
from langchain_aws import ChatBedrockConverse

llm = ChatBedrockConverse(
    model="us.anthropic.claude-sonnet-4-20250514-v1:0",
    region_name="us-west-2",
)
```

Claude/Anthropic accepts `{"type": "object"}` without `properties`. The schema passes through unchanged and works fine.

### 6. Why Azure OpenAI Fails

The ported sample uses:

```python
from langchain_openai import AzureChatOpenAI

llm = AzureChatOpenAI(
    azure_endpoint=azure_endpoint,
    azure_deployment=model_name,
    api_version="2024-10-21",
)
```

OpenAI's strict mode **requires** `{"type": "object", "properties": {}}`. The missing `properties` field causes immediate rejection.

## The Bug Chain

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. Neo4j MCP Server (Go)                                                │
│    - get-schema tool has no parameters                                  │
│    - No WithInputSchema[]() call                                        │
│    - mcp-go library generates: {"type": "object"} (missing properties!) │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. langchain-mcp-adapters (Python)                                      │
│    - Receives tool with broken schema                                   │
│    - Converts to StructuredTool                                         │
│    - Does NOT fix/normalize schemas                                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. LangGraph create_agent() (Python)                                    │
│    - Accepts tools as-is                                                │
│    - Passes to LLM via bind_tools()                                     │
│    - Does NOT fix/normalize schemas                                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 4. AzureChatOpenAI (Python)                                             │
│    - Converts tools to OpenAI function format                           │
│    - Sends: {"type": "object"} (still broken)                           │
│    - OpenAI API rejects: "object schema missing properties"             │
└─────────────────────────────────────────────────────────────────────────┘
```

## Possible Solutions

### Option 1: Fix at Source (Neo4j MCP Server)

**Best solution.** Fix the mcp-go library or Neo4j MCP server to always include `properties: {}`.

**Location:** `/Users/ryanknight/projects/mcp/internal/tools/cypher/get_schema_spec.go`

```go
// Add explicit empty input schema
func GetSchemaSpec() mcp.Tool {
    return mcp.NewTool("get-schema",
        mcp.WithDescription(`...`),
        mcp.WithInputSchema[struct{}](),  // Explicit empty schema
    )
}
```

**Pros:** Fixes for all consumers
**Cons:** Requires upstream change to Neo4j MCP server

### Option 2: Fix in langchain-mcp-adapters

Add schema normalization in the adapter layer.

**Pros:** Fixes for all MCP servers
**Cons:** Requires upstream PR to langchain-mcp-adapters

### Option 3: Fix in Client Code (Workaround)

Transform tools after `get_tools()` to add `properties: {}`.

```python
from langchain_core.tools import StructuredTool
from pydantic import BaseModel

class EmptyInput(BaseModel):
    """No parameters required."""
    pass

def fix_empty_schema_tools(tools: list) -> list:
    """Add properties field to tools with empty schemas for OpenAI compatibility."""
    fixed = []
    for tool in tools:
        if not tool.args:  # Empty args = no parameters
            # Recreate with valid schema
            fixed.append(StructuredTool.from_function(
                name=tool.name,
                description=tool.description,
                func=lambda **_: tool.invoke({}),
                coroutine=lambda **_: tool.ainvoke({}),
                args_schema=EmptyInput,
            ))
        else:
            fixed.append(tool)
    return fixed

tools = fix_empty_schema_tools(await client.get_tools())
```

**Pros:** Works immediately
**Cons:** Workaround, not a real fix; fragile to tool API changes

### Option 4: Use Anthropic on Azure (If Available)

Switch to Claude on Azure instead of GPT-4.

**Pros:** No code changes needed
**Cons:** Claude may not be available on Azure in all regions

### Option 5: Patch LangChain's Tool Conversion

Override the tool-to-function conversion to fix schemas.

```python
from langchain_openai.chat_models.base import _convert_to_openai_tool

original_convert = _convert_to_openai_tool

def patched_convert(tool):
    result = original_convert(tool)
    params = result.get("function", {}).get("parameters", {})
    if params.get("type") == "object" and "properties" not in params:
        params["properties"] = {}
    return result

# Monkey-patch
langchain_openai.chat_models.base._convert_to_openai_tool = patched_convert
```

**Pros:** Transparent fix
**Cons:** Fragile; depends on LangChain internals

## Recommended Solution

**Short-term:** Option 3 (Client workaround) - Gets it working now

**Long-term:** Option 1 (Fix Neo4j MCP Server) - File issue/PR upstream

## Related Issues

- [github/github-mcp-server#1548](https://github.com/github/github-mcp-server/issues/1548) - Same issue, fixed in v0.24.1
- [langchain-ai/langchainjs#8297](https://github.com/langchain-ai/langchainjs/issues/8297) - MCP tools schema issues
- [langchain-ai/langchainjs#8467](https://github.com/langchain-ai/langchainjs/issues/8467) - MCP adapter schema validation errors

## Key Insight

**The original AWS sample was never tested with OpenAI.** It was built for Claude on Bedrock, which is lenient. The schema bug exists in the MCP server but is masked by Anthropic's tolerance.

This is a **provider compatibility issue**, not a code bug in the sample. The sample is correct; the MCP server's schema output is technically invalid per OpenAI's requirements.

## Schema Comparison

### What MCP Server Returns (Invalid for OpenAI)
```json
{
  "name": "get-schema",
  "description": "Retrieve the schema...",
  "inputSchema": {
    "type": "object"
  }
}
```

### What OpenAI Requires (Valid)
```json
{
  "name": "get-schema",
  "description": "Retrieve the schema...",
  "inputSchema": {
    "type": "object",
    "properties": {}
  }
}
```

The difference is literally 17 characters: `, "properties": {}`.
