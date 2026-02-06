// =============================================================================
// Neo4j MCP Server - Azure Container Apps Deployment
// Main Bicep template orchestrating all modules for the demo deployment.
//
// Resources created:
// - User-Assigned Managed Identity (for ACR and Key Vault access)
// - Log Analytics Workspace (for container telemetry)
// - Azure Container Registry (for storing Docker images)
// - Azure Key Vault (for secrets)
// - Container Apps Environment
// - Container App (Neo4j MCP Server)
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
// Secure Parameters (Secrets from .env file)
// =============================================================================

@description('Neo4j database connection URI')
@secure()
param neo4jUri string

@description('Neo4j database username')
@secure()
param neo4jUsername string

@description('Neo4j database password')
@secure()
param neo4jPassword string

@description('Neo4j database name')
@secure()
param neo4jDatabase string

@description('MCP API key for authentication')
@secure()
param mcpApiKey string

@description('Neo4j MCP Server container image (e.g., myacr.azurecr.io/neo4j-mcp-server:latest)')
param mcpServerImage string = ''

@description('Auth proxy container image (e.g., myacr.azurecr.io/mcp-auth-proxy:latest)')
param authProxyImage string = ''

@description('Principal ID of the deploying user (for Key Vault write access during redeploy)')
param deployerPrincipalId string = ''

// =============================================================================
// Variables
// =============================================================================

// Generate unique suffix based on resource group ID for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Deployment timestamp for resources that need unique names on each deployment
param deploymentTimestamp string = utcNow('yyyyMMddHHmmss')

// Resource names
var managedIdentityName = '${baseName}-identity-${environment}'
var logAnalyticsName = '${baseName}-logs-${environment}'
var containerRegistryName = '${baseName}acr${uniqueSuffix}'  // ACR names must be alphanumeric only
// Key Vault names: 3-24 chars, alphanumeric and hyphens only
// Use timestamp to generate unique name each deployment (avoids soft-delete conflicts)
// Formula: 'kv-' (3) + take(uniqueSuffix, 6) + '-' (1) + take(timestamp, 10) = 20 chars max
var keyVaultName = 'kv-${take(uniqueSuffix, 6)}-${take(deploymentTimestamp, 10)}'
var containerEnvironmentName = '${baseName}-env-${environment}'
var containerAppName = '${baseName}-app-${environment}'

// Determine container images - use provided or construct default from ACR
var effectiveMcpServerImage = !empty(mcpServerImage) ? mcpServerImage : '${containerRegistryName}.azurecr.io/neo4j-mcp-server:latest'
var effectiveAuthProxyImage = !empty(authProxyImage) ? authProxyImage : '${containerRegistryName}.azurecr.io/mcp-auth-proxy:latest'

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
// Phase 2: Secrets and Security
// =============================================================================

// Azure Key Vault
// Stores Neo4j connection credentials and MCP API key
// Grants Key Vault Secrets User role to managed identity
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    identityPrincipalId: managedIdentity.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
    neo4jUri: neo4jUri
    neo4jUsername: neo4jUsername
    neo4jPassword: neo4jPassword
    neo4jDatabase: neo4jDatabase
    mcpApiKey: mcpApiKey
  }
}

// =============================================================================
// Phase 3: Container Environment
// =============================================================================

// Reference to Log Analytics workspace for listKeys
resource logAnalyticsWorkspaceRef 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: logAnalyticsName
  dependsOn: [
    logAnalytics
  ]
}

// Container Apps Environment
// Linked to Log Analytics for telemetry and monitoring
module containerEnvironment 'modules/container-environment.bicep' = {
  name: 'deploy-container-environment'
  params: {
    name: containerEnvironmentName
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalyticsWorkspaceRef.listKeys().primarySharedKey
  }
}

// =============================================================================
// Phase 4: Container App
// =============================================================================

// Container App - Neo4j MCP Server with Auth Proxy
// Architecture:
// - Nginx auth proxy (port 8080): Validates API keys, proxies with Basic Auth
// - MCP server (port 8000): Handles MCP protocol requests to Neo4j
// Configured with:
// - Fixed 1 replica for demo consistency
// - Managed identity for ACR pull and Key Vault access
// - Key Vault references for sensitive environment variables
// - External HTTPS ingress through auth proxy
module containerApp 'modules/container-app.bicep' = {
  name: 'deploy-container-app'
  params: {
    name: containerAppName
    location: location
    tags: tags
    containerAppsEnvironmentId: containerEnvironment.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    mcpServerImage: effectiveMcpServerImage
    authProxyImage: effectiveAuthProxyImage
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    keyVaultName: keyVault.outputs.name
  }
}

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

// Phase 2 Outputs
@description('Key Vault name')
output keyVaultName string = keyVault.outputs.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.vaultUri

// Phase 3 Outputs
@description('Container Apps Environment ID')
output containerEnvironmentId string = containerEnvironment.outputs.id

@description('Container Apps Environment default domain')
output containerEnvironmentDefaultDomain string = containerEnvironment.outputs.defaultDomain

// Phase 4 Outputs
@description('Container App name')
output containerAppName string = containerApp.outputs.name

@description('Container App FQDN')
output containerAppFqdn string = containerApp.outputs.fqdn

@description('Container App URL')
output containerAppUrl string = containerApp.outputs.url

@description('MCP Server container image deployed')
output mcpServerImage string = effectiveMcpServerImage

@description('Auth proxy container image deployed')
output authProxyImage string = effectiveAuthProxyImage
