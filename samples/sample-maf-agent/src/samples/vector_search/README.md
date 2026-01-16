# Vector Search Samples

Demonstrates semantic similarity search using vector embeddings with Neo4j.

## Samples

### main.py - Vector Context Provider

Vector search context provider using Azure AI embeddings for semantic similarity.

```bash
uv run start-samples 4
```

**Features:**
- Semantic similarity using embeddings
- Azure AI embedding integration
- Top-k result retrieval

### semantic_search.py - Semantic Search Demo

Direct semantic search demonstration showing embedding generation and similarity matching.

```bash
uv run start-samples 2
```

## Required Environment Variables

```
AZURE_AI_PROJECT_ENDPOINT=https://your-project.cognitiveservices.azure.com
AZURE_AI_MODEL_NAME=gpt-4o
AZURE_AI_EMBEDDING_NAME=text-embedding-ada-002
NEO4J_URI=neo4j+s://xxx.databases.neo4j.io
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=your-password
NEO4J_VECTOR_INDEX_NAME=chunkEmbeddings
```
