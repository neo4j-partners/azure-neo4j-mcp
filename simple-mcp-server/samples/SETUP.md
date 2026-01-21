# Neo4j Database Setup

This guide walks you through setting up the Neo4j Aura database with the SEC 10-K filings knowledge graph.

## Part 1: Restore the Backup

After your Aura instance is running, restore the pre-built knowledge graph:

1. **Download the backup file first**
   - Download `finance_data.backup` from [neo4j-partners/workshop-financial-data](https://github.com/neo4j-partners/workshop-financial-data/tree/main/backup)

2. Go to your instance in the [Aura Console](https://console.neo4j.io)

3. Click the **...** menu on your instance and select **Backup & restore**

   ![](images/backup_restore.png)

4. Click **Upload backup** to open the upload dialog, then drag the backup file into the dialog:

   ![](images/restore_drag.png)

5. Wait for the restore to complete - your instance will restart with the SEC 10-K filings knowledge graph

The backup contains:
- SEC 10-K filing documents from major companies (Apple, Microsoft, NVIDIA, etc.)
- Extracted entities: Companies, Risk Factors, Products, Executives, Financial Metrics
- Asset manager ownership data
- Text chunks with vector embeddings for semantic search

## Part 2: Explore the Knowledge Graph

Use Neo4j Explore to visually navigate your graph:

1. Open the Neo4j Aura Console and click **Explore** on your instance
2. Search for patterns between asset managers, companies, and risk factors
3. Apply graph algorithms like Degree Centrality
4. Identify key entities through visual analysis

### Sample Queries

Try these Cypher queries in the Neo4j Browser to explore the data:

```cypher
// View the data model
CALL db.schema.visualization()

// Find all companies
MATCH (c:Company) RETURN c.name LIMIT 10

// Find risk factors for a company
MATCH (c:Company)-[:HAS_RISK]->(r:RiskFactor)
WHERE c.name CONTAINS 'Apple'
RETURN c.name, r.description LIMIT 5

// Find asset managers and their holdings
MATCH (am:AssetManager)-[:OWNS]->(c:Company)
RETURN am.name, collect(c.name) AS holdings LIMIT 10
```
