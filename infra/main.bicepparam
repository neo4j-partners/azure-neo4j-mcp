// =============================================================================
// Neo4j MCP Server - Bicep Parameter File
// Configure deployment parameters for the Azure Container Apps deployment.
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
// Note: environment tag matches the environment parameter above
param tags = {
  project: 'neo4j-mcp-server'
  environment: environment
  deployedBy: 'bicep'
}
