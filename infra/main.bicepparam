// =============================================================================
// Neo4j MCP Server - Bicep Parameter File
// Configure deployment parameters for the Azure Container Apps deployment.
// =============================================================================
//
// IMPORTANT: Secure parameters are read from environment variables at deployment
// time using readEnvironmentVariable(). The deploy.sh script exports these from
// the .env file before running the deployment.
//
// Required environment variables:
//   - NEO4J_URI: Neo4j connection URI (e.g., neo4j+s://xxx.databases.neo4j.io)
//   - NEO4J_USERNAME: Neo4j username
//   - NEO4J_PASSWORD: Neo4j password
//   - NEO4J_DATABASE: Neo4j database name (defaults to 'neo4j')
//   - MCP_API_KEY: API key for MCP server authentication
//
// Optional environment variables:
//   - MCP_SERVER_IMAGE: Full container image path (defaults to ACR image)
//   - AUTH_PROXY_IMAGE: Full auth proxy image path (defaults to ACR image)
// =============================================================================

using 'main.bicep'

// Azure region for all resources
// Recommended: Use a region close to your Neo4j database for lower latency
param location = 'eastus'

// Base name for all resources
// Used to generate unique names for each resource
param baseName = 'neo4jmcp'

// Environment name
// Affects resource naming and can be used for environment-specific configurations
param environment = 'dev'

// Tags applied to all resources
// Add custom tags as needed for cost tracking, ownership, etc.
param tags = {
  project: 'neo4j-mcp-server'
  environment: environment
  deployedBy: 'bicep'
}

// =============================================================================
// Secure Parameters - Read from environment variables
// =============================================================================

// Neo4j connection credentials (read from environment)
param neo4jUri = readEnvironmentVariable('NEO4J_URI')
param neo4jUsername = readEnvironmentVariable('NEO4J_USERNAME')
param neo4jPassword = readEnvironmentVariable('NEO4J_PASSWORD')
param neo4jDatabase = readEnvironmentVariable('NEO4J_DATABASE', 'neo4j')

// MCP API key for client authentication
param mcpApiKey = readEnvironmentVariable('MCP_API_KEY')

// =============================================================================
// Container Images - Read from environment or use defaults
// =============================================================================

// Container images (empty string = use ACR default in main.bicep)
param mcpServerImage = readEnvironmentVariable('MCP_SERVER_IMAGE', '')
param authProxyImage = readEnvironmentVariable('AUTH_PROXY_IMAGE', '')

// =============================================================================
// Deployer Access - For Key Vault write permissions during redeploy
// =============================================================================

// Principal ID of the deploying user (grants Key Vault Secrets Officer role)
param deployerPrincipalId = readEnvironmentVariable('DEPLOYER_PRINCIPAL_ID', '')
