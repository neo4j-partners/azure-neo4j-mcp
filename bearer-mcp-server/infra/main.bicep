// =============================================================================
// Neo4j MCP Server - Bearer Token Authentication Deployment
// Main Bicep template for single-container deployment with native bearer auth.
//
// This deployment uses the Neo4j MCP server's built-in HTTP mode with bearer
// token authentication. Clients authenticate via their identity provider and
// pass JWT tokens directly to the MCP server, which forwards them to Neo4j.
//
// Key Differences from simple-mcp-server:
// - Single container (no Nginx auth proxy)
// - No static API key or database credentials stored
// - Bearer tokens passed through to Neo4j for SSO/OIDC authentication
// - Requires Neo4j Enterprise with OIDC configured
//
// Resources created:
// - User-Assigned Managed Identity (for ACR access)
// - Log Analytics Workspace (for container telemetry)
// - Azure Container Registry (for storing Docker images)
// - Azure Key Vault (minimal - only connection info, no credentials)
// - Container Apps Environment
// - Container App (single Neo4j MCP Server container)
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
  project: 'neo4j-mcp-server-bearer'
  environment: environment
  deployedBy: 'bicep'
  authMode: 'bearer-token'
}

// =============================================================================
// Connection Parameters (No Credentials - Bearer Auth Mode)
// =============================================================================

@description('Neo4j database connection URI (e.g., neo4j+s://xxx.databases.neo4j.io)')
@secure()
param neo4jUri string

@description('Neo4j database name (default: neo4j)')
param neo4jDatabase string = 'neo4j'

@description('Neo4j MCP Server container image (e.g., myacr.azurecr.io/neo4j-mcp-server:latest)')
param mcpServerImage string = ''

@description('Principal ID of the deploying user (for Key Vault access during deployment)')
param deployerPrincipalId string = ''

@description('Enable read-only mode (disables write-cypher tool)')
param readOnlyMode bool = true

@description('Allowed CORS origins (comma-separated, or * for all)')
param allowedOrigins string = ''

// =============================================================================
// Variables
// =============================================================================

// Generate unique suffix based on resource group ID for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Deployment timestamp for resources that need unique names on each deployment
param deploymentTimestamp string = utcNow('yyyyMMddHHmmss')

// Resource names - using 'b' prefix to distinguish from simple-mcp-server and keep names short
// Container App name max length is 32 characters, so use take() to ensure we stay within limits
var managedIdentityName = '${baseName}-b-id-${environment}'
var logAnalyticsName = '${baseName}-b-logs-${environment}'
var containerRegistryName = '${baseName}bacr${uniqueSuffix}'
var keyVaultName = 'kv-b-${take(uniqueSuffix, 4)}-${take(deploymentTimestamp, 10)}'
var containerEnvironmentName = '${baseName}-b-env-${environment}'
// Ensure container app name is max 32 chars: baseName(max 20) + '-b-' (3) + env (max 7) = 30, but use take() for safety
var containerAppName = take('${baseName}-b-${environment}', 32)

// Determine container image - use provided or construct default from ACR
var effectiveMcpServerImage = !empty(mcpServerImage) ? mcpServerImage : '${containerRegistryName}.azurecr.io/neo4j-mcp-server:latest'

// =============================================================================
// Phase 1: Foundation Resources
// =============================================================================

// User-Assigned Managed Identity
// Used for ACR pull - Key Vault access not needed since no secrets are retrieved at runtime
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
    retentionInDays: 30
    skuName: 'PerGB2018'
  }
}

// Azure Container Registry
// Stores the Neo4j MCP server Docker image
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'deploy-container-registry'
  params: {
    name: containerRegistryName
    location: location
    tags: tags
    sku: 'Basic'
    acrPullPrincipalId: managedIdentity.outputs.principalId
  }
}

// =============================================================================
// Phase 2: Configuration Storage (Minimal - No Credentials)
// =============================================================================

// Azure Key Vault
// In bearer mode, only stores connection info (URI, database name)
// NO credentials stored - authentication via bearer tokens at runtime
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    deployerPrincipalId: deployerPrincipalId
    neo4jUri: neo4jUri
    neo4jDatabase: neo4jDatabase
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
// Phase 4: Container App (Single Container - No Proxy)
// =============================================================================

// Container App - Neo4j MCP Server with Bearer Token Authentication
// Single container deployment - no Nginx proxy needed
// Authentication handled by MCP server passing tokens to Neo4j
module containerApp 'modules/container-app.bicep' = {
  name: 'deploy-container-app'
  params: {
    name: containerAppName
    location: location
    tags: tags
    containerAppsEnvironmentId: containerEnvironment.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    mcpServerImage: effectiveMcpServerImage
    containerRegistryLoginServer: containerRegistry.outputs.loginServer
    neo4jUri: neo4jUri
    neo4jDatabase: neo4jDatabase
    readOnlyMode: readOnlyMode
    allowedOrigins: allowedOrigins
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure region')
output location string = location

@description('Authentication mode')
output authMode string = 'bearer-token'

// Phase 1 Outputs
@description('Managed Identity resource ID')
output managedIdentityId string = managedIdentity.outputs.id

@description('Managed Identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.id

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

@description('MCP endpoint URL')
output mcpEndpoint string = '${containerApp.outputs.url}/mcp'

@description('MCP Server container image deployed')
output mcpServerImage string = effectiveMcpServerImage
