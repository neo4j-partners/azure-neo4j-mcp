# Basic Fulltext Search Samples

Demonstrates fulltext search with Neo4j using the Lucene query syntax.

## Samples

### main.py - Basic Context Provider

Basic fulltext search context provider that passes user queries directly to Neo4j's fulltext index.

```bash
uv run start-samples 3
```

**Features:**
- Fulltext search using Lucene syntax
- Automatic stop word filtering
- Message history windowing

### azure_thread_memory.py - Azure Thread Memory

Demonstrates Azure Agent Framework thread memory without Neo4j. Useful for testing agent configuration independently.

```bash
uv run start-samples 1
```

## Required Environment Variables

```
AZURE_AI_PROJECT_ENDPOINT=https://your-project.cognitiveservices.azure.com
AZURE_AI_MODEL_NAME=gpt-4o
NEO4J_URI=neo4j+s://xxx.databases.neo4j.io
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=your-password
NEO4J_FULLTEXT_INDEX_NAME=search_chunks
```
