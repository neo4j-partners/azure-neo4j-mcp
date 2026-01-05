// =============================================================================
// Neo4j MCP Server - Azure Container Apps Deployment
// Main Bicep template orchestrating all modules for the demo deployment.
//
// Resources created:
// - User-Assigned Managed Identity (for ACR and Key Vault access)
// - Log Analytics Workspace (for container telemetry)
// - Azure Container Registry (for storing Docker images)
// - [Phase 2] Azure Key Vault (for secrets)
// - [Phase 3] Container Apps Environment
// - [Phase 4] Container App (Neo4j MCP Server)
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources (used to generate unique names)')
@minLength(3)
@maxLength(20)
param baseName string = 'neo4jmcp'

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  project: 'neo4j-mcp-server'
  environment: environment
  deployedBy: 'bicep'
}

// =============================================================================
// Variables
// =============================================================================

// Generate unique suffix based on resource group ID for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Resource names
var managedIdentityName = '${baseName}-identity-${environment}'
var logAnalyticsName = '${baseName}-logs-${environment}'
var containerRegistryName = '${baseName}acr${uniqueSuffix}'  // ACR names must be alphanumeric only

// =============================================================================
// Phase 1: Foundation Resources
// =============================================================================

// User-Assigned Managed Identity
// Created first as other resources reference it for RBAC
module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'deploy-managed-identity'
  params: {
    name: managedIdentityName
    location: location
    tags: tags
  }
}

// Log Analytics Workspace
// Required by Container Apps Environment for telemetry
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    retentionInDays: 30  // Minimum for demo, reduce costs
    skuName: 'PerGB2018'
  }
}

// Azure Container Registry
// Stores the Neo4j MCP server Docker image
// Grants AcrPull role to managed identity for secure image pulls
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'deploy-container-registry'
  params: {
    name: containerRegistryName
    location: location
    tags: tags
    sku: 'Basic'  // Sufficient for demo
    acrPullPrincipalId: managedIdentity.outputs.principalId
  }
}

// =============================================================================
// Phase 2: Secrets and Security (TODO)
// =============================================================================

// Key Vault module will be added here

// =============================================================================
// Phase 3: Container Environment (TODO)
// =============================================================================

// Container Apps Environment module will be added here

// =============================================================================
// Phase 4: Container App (TODO)
// =============================================================================

// Container App module will be added here

// =============================================================================
// Outputs
// =============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure region')
output location string = location

// Phase 1 Outputs
@description('Managed Identity resource ID')
output managedIdentityId string = managedIdentity.outputs.id

@description('Managed Identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Managed Identity client ID')
output managedIdentityClientId string = managedIdentity.outputs.clientId

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.id

@description('Log Analytics Workspace customer ID')
output logAnalyticsCustomerId string = logAnalytics.outputs.customerId

@description('Container Registry name')
output containerRegistryName string = containerRegistry.outputs.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer
