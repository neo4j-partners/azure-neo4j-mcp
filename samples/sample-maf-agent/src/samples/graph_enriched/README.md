# Graph-Enriched Search Sample

Demonstrates combining initial search with graph traversal for rich context.

## Sample

### main.py - Graph-Enriched Context Provider

After initial vector or fulltext search, executes custom Cypher queries to traverse relationships and enrich results with connected data.

```bash
uv run start-samples 5
```

**Features:**
- Initial search (vector or fulltext)
- Custom Cypher retrieval queries
- Relationship traversal for context enrichment
- Returns connected entities with search results

## Example Retrieval Query

```cypher
MATCH (node)-[:FROM_DOCUMENT]->(doc:Document)-[:FILED_BY]->(company:Company)
RETURN node.text AS text, score,
       doc.title AS title,
       company.name AS company
ORDER BY score DESC
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
