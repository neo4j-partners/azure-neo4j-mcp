// =============================================================================
// Bearer Token MCP Server - Bicep Parameters
// Uses readEnvironmentVariable() to load parameters from environment variables.
//
// Required environment variables:
// - NEO4J_URI: Neo4j database connection URI
//
// Optional environment variables:
// - NEO4J_DATABASE: Database name (default: neo4j)
// - BASE_NAME: Base name for resources (default: neo4jmcp)
// - ENVIRONMENT: Environment name (default: dev)
// - MCP_SERVER_IMAGE: Container image override (default: docker.io/mcp/neo4j:latest)
// - DEPLOYER_PRINCIPAL_ID: Principal ID for Key Vault access
// - NEO4J_READ_ONLY: Enable read-only mode (default: true)
// - CORS_ALLOWED_ORIGINS: Allowed CORS origins
// =============================================================================

using 'main.bicep'

// Required: Neo4j connection URI
param neo4jUri = readEnvironmentVariable('NEO4J_URI')

// Optional: Database name
param neo4jDatabase = readEnvironmentVariable('NEO4J_DATABASE', 'neo4j')

// Optional: Naming and environment
param baseName = readEnvironmentVariable('BASE_NAME', 'neo4jmcp')
param environment = readEnvironmentVariable('ENVIRONMENT', 'dev')

// Optional: Container image override (defaults to official Docker Hub image)
param mcpServerImage = readEnvironmentVariable('MCP_SERVER_IMAGE', 'docker.io/mcp/neo4j:latest')

// Optional: Deployer access to Key Vault
param deployerPrincipalId = readEnvironmentVariable('DEPLOYER_PRINCIPAL_ID', '')

// Optional: Read-only mode (default: true for safety)
param readOnlyMode = readEnvironmentVariable('NEO4J_READ_ONLY', 'true') == 'true'

// Optional: CORS configuration
param allowedOrigins = readEnvironmentVariable('CORS_ALLOWED_ORIGINS', '')
